#
# This content script must be run prior to domReady so that we perform some operations very early.
#

isEnabledForUrl = true
isIncognitoMode = chrome.extension.inIncognitoContext
normalMode = null

# We track whther the current window has the focus or not.
windowIsFocused = do ->
  windowHasFocus = null
  DomUtils.documentReady -> windowHasFocus = document.hasFocus()
  window.addEventListener "focus", (event) -> windowHasFocus = true if event.target == window; true
  window.addEventListener "blur", (event) -> windowHasFocus = false if event.target == window; true
  -> windowHasFocus

# The types in <input type="..."> that we consider for focusInput command. Right now this is recalculated in
# each content script. Alternatively we could calculate it once in the background page and use a request to
# fetch it each time.
# Should we include the HTML5 date pickers here?

# The corresponding XPath for such elements.
textInputXPath = (->
  textInputTypes = [ "text", "search", "email", "url", "number", "password", "date", "tel" ]
  inputElements = ["input[" +
    "(" + textInputTypes.map((type) -> '@type="' + type + '"').join(" or ") + "or not(@type))" +
    " and not(@disabled or @readonly)]",
    "textarea", "*[@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"]
  DomUtils.makeXPath(inputElements)
)()

# This is set by Frame.registerFrameId(). A frameId of 0 indicates that this is the top frame in the tab.
frameId = null

# For debugging only. This writes to the Vimium log page, the URL of whichis shown on the console on the
# background page.
bgLog = (args...) ->
  args = (arg.toString() for arg in args)
  Frame.postMessage "log", message: args.join " "

# If an input grabs the focus before the user has interacted with the page, then grab it back (if the
# grabBackFocus option is set).
class GrabBackFocus extends Mode

  constructor: ->
    exitEventHandler = =>
      @alwaysContinueBubbling =>
        @exit()
        chrome.runtime.sendMessage handler: "sendMessageToFrames", message: name: "userIsInteractingWithThePage"

    super
      name: "grab-back-focus"
      keydown: exitEventHandler

    @push
      _name: "grab-back-focus-mousedown"
      mousedown: exitEventHandler

    Settings.use "grabBackFocus", (grabBackFocus) =>
      # It is possible that this mode exits (e.g. due to a key event) before the settings are ready -- in
      # which case we should not install this grab-back-focus watcher.
      if @modeIsActive
        if grabBackFocus
          @push
            _name: "grab-back-focus-focus"
            focus: (event) => @grabBackFocus event.target
          # An input may already be focused. If so, grab back the focus.
          @grabBackFocus document.activeElement if document.activeElement
        else
          @exit()

    # This mode is active in all frames.  A user might have begun interacting with one frame without other
    # frames detecting this.  When one GrabBackFocus mode exits, we broadcast a message to inform all
    # GrabBackFocus modes that they should exit; see #2296.
    chrome.runtime.onMessage.addListener listener = ({name}) =>
      if name == "userIsInteractingWithThePage"
        chrome.runtime.onMessage.removeListener listener
        @exit() if @modeIsActive
      false # We will not be calling sendResponse.

  grabBackFocus: (element) ->
    return @continueBubbling unless DomUtils.isFocusable element
    element.blur()
    @suppressEvent

# Pages can load new content dynamically and change the displayed URL using history.pushState. Since this can
# often be indistinguishable from an actual new page load for the user, we should also re-start GrabBackFocus
# for these as well. This fixes issue #1622.
handlerStack.push
  _name: "GrabBackFocus-pushState-monitor"
  click: (event) ->
    # If a focusable element is focused, the user must have clicked on it. Retain focus and bail.
    return true if DomUtils.isFocusable document.activeElement

    target = event.target
    while target
      # Often, a link which triggers a content load and url change with javascript will also have the new
      # url as it's href attribute.
      if target.tagName == "A" and
         target.origin == document.location.origin and
         # Clicking the link will change the url of this frame.
         (target.pathName != document.location.pathName or
          target.search != document.location.search) and
         (target.target in ["", "_self"] or
          (target.target == "_parent" and window.parent == window) or
          (target.target == "_top" and window.top == window))
        return new GrabBackFocus()
      else
        target = target.parentElement
    true

class NormalMode extends KeyHandlerMode
  constructor: (options = {}) ->
    super extend options,
      name: "normal"
      indicator: false # There is no mode indicator in normal mode.
      commandHandler: @commandHandler.bind this

    chrome.storage.local.get "normalModeKeyStateMapping", (items) =>
      @setKeyMapping items.normalModeKeyStateMapping

    chrome.storage.onChanged.addListener (changes, area) =>
      if area == "local" and changes.normalModeKeyStateMapping?.newValue
        @setKeyMapping changes.normalModeKeyStateMapping.newValue

    # Initialize components which normal mode depends upon.
    Scroller.init()
    FindModeHistory.init()

  commandHandler: ({command: registryEntry, count}) ->
    count *= registryEntry.options.count ? 1
    count = 1 if registryEntry.noRepeat

    if registryEntry.repeatLimit? and registryEntry.repeatLimit < count
      return unless confirm """
        You have asked Vimium to perform #{count} repetitions of the command: #{registryEntry.description}.\n
        Are you sure you want to continue?"""

    if registryEntry.topFrame
      # We never return to a UI-component frame (e.g. the help dialog), it might have lost the focus.
      sourceFrameId = if window.isVimiumUIComponent then 0 else frameId
      chrome.runtime.sendMessage
        handler: "sendMessageToFrames", message: {name: "runInTopFrame", sourceFrameId, registryEntry}
    else if registryEntry.background
      chrome.runtime.sendMessage {handler: "runBackgroundCommand", registryEntry, count}
    else
      Utils.invokeCommandString registryEntry.command, count, {registryEntry}

installModes = ->
  # Install the permanent modes. The permanently-installed insert mode tracks focus/blur events, and
  # activates/deactivates itself accordingly.
  normalMode = new NormalMode
  new InsertMode permanent: true
  new GrabBackFocus if isEnabledForUrl
  normalMode # Return the normalMode object (for the tests).

initializeOnEnabledStateKnown = (isEnabledForUrl) ->
  installModes() unless normalMode
  if isEnabledForUrl
    # We only initialize (and activate) the Vomnibar in the top frame.  Also, we do not initialize the
    # Vomnibar until we know that Vimium is enabled.  Thereafter, there's no more initialization to do.
    DomUtils.documentComplete Vomnibar.init.bind Vomnibar if DomUtils.isTopFrame()
    initializeOnEnabledStateKnown = ->

#
# Complete initialization work that should be done prior to DOMReady.
#
initializePreDomReady = ->
  installListeners()
  Frame.init()
  checkIfEnabledForUrl document.hasFocus()

  requestHandlers =
    focusFrame: (request) -> if (frameId == request.frameId) then focusThisFrame request
    getScrollPosition: (ignoredA, ignoredB, sendResponse) ->
      sendResponse scrollX: window.scrollX, scrollY: window.scrollY if frameId == 0
    setScrollPosition: setScrollPosition
    frameFocused: -> # A frame has received the focus; we don't care here (UI components handle this).
    checkEnabledAfterURLChange: checkEnabledAfterURLChange
    runInTopFrame: ({sourceFrameId, registryEntry}) ->
      Utils.invokeCommandString registryEntry.command, sourceFrameId, registryEntry if DomUtils.isTopFrame()
    linkHintsMessage: (request) -> HintCoordinator[request.messageType] request

  chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
    # Some requests intended for the background page are delivered to the options page too; ignore them.
    unless request.handler and not request.name
      # Some request are handled elsewhere; ignore them too.
      unless request.name in ["userIsInteractingWithThePage"]
        if isEnabledForUrl or request.name in ["checkEnabledAfterURLChange", "runInTopFrame"]
          requestHandlers[request.name] request, sender, sendResponse
    false # Ensure that the sendResponse callback is freed.

# Wrapper to install event listeners.  Syntactic sugar.
installListener = (element, event, callback) ->
  element.addEventListener(event, ->
    if isEnabledForUrl then callback.apply(this, arguments) else true
  , true)

#
# Installing or uninstalling listeners is error prone. Instead we elect to check isEnabledForUrl each time so
# we know whether the listener should run or not.
# Run this as early as possible, so the page can't register any event handlers before us.
# Note: We install the listeners even if Vimium is disabled.  See comment in commit
# 6446cf04c7b44c3d419dc450a73b60bcaf5cdf02.
#
installListeners = Utils.makeIdempotent ->
  # Key event handlers fire on window before they do on document. Prefer window for key events so the page
  # can't set handlers to grab the keys before us.
  for type in ["keydown", "keypress", "keyup", "click", "focus", "blur", "mousedown", "scroll"]
    do (type) -> installListener window, type, (event) -> handlerStack.bubbleEvent type, event
  installListener document, "DOMActivate", (event) -> handlerStack.bubbleEvent 'DOMActivate', event

#
# Whenever we get the focus:
# - Tell the background page this frame's URL.
# - Check if we should be enabled.
#
onFocus = (event) ->
  if event.target == window
    chrome.runtime.sendMessage handler: "frameFocused"
    checkIfEnabledForUrl true

# We install these listeners directly (that is, we don't use installListener) because we still need to receive
# events when Vimium is not enabled.
window.addEventListener "focus", onFocus
window.addEventListener "hashchange", onFocus

initializeOnDomReady = ->
  # Tell the background page we're in the domReady state.
  Frame.postMessage "domReady"

Frame =
  port: null
  listeners: {}

  addEventListener: (handler, callback) -> @listeners[handler] = callback
  postMessage: (handler, request = {}) -> @port.postMessage extend request, {handler}
  linkHintsMessage: (request) -> HintCoordinator[request.messageType] request
  registerFrameId: ({chromeFrameId}) ->
    frameId = window.frameId = chromeFrameId
    # We register a frame immediately only if it is focused or its window isn't tiny.  We register tiny
    # frames later, when necessary.  This affects focusFrame() and link hints.
    if windowIsFocused() or not DomUtils.windowIsTooSmall()
      Frame.postMessage "registerFrame"
    else
      postRegisterFrame = ->
        window.removeEventListener "focus", focusHandler
        window.removeEventListener "resize", resizeHandler
        Frame.postMessage "registerFrame"
      window.addEventListener "focus", focusHandler = ->
        postRegisterFrame() if event.target == window
      window.addEventListener "resize", resizeHandler = ->
        postRegisterFrame() unless DomUtils.windowIsTooSmall()

  init: ->
    @port = chrome.runtime.connect name: "frames"

    @port.onMessage.addListener (request) =>
      (@listeners[request.handler] ? this[request.handler]) request

    # We disable the content scripts when we lose contact with the background page, or on unload.
    @port.onDisconnect.addListener disconnect = Utils.makeIdempotent => @disconnect()
    window.addEventListener "unload", disconnect

  disconnect: ->
    try @postMessage "unregisterFrame"
    try @port.disconnect()
    @postMessage = @disconnect = ->
    @port = null
    @listeners = {}
    HintCoordinator.exit isSuccess: false
    handlerStack.reset()
    isEnabledForUrl = false
    window.removeEventListener "focus", onFocus
    window.removeEventListener "hashchange", onFocus

setScrollPosition = ({ scrollX, scrollY }) ->
  DomUtils.documentReady ->
    if DomUtils.isTopFrame()
      window.focus()
      document.body.focus()
      if 0 < scrollX or 0 < scrollY
        Marks.setPreviousPosition()
        window.scrollTo scrollX, scrollY

flashFrame = ->
DomUtils.documentReady ->
  # Create a shadow DOM wrapping the frame so the page's styles don't interfere with ours.
  highlightedFrameElement = DomUtils.createElement "div"
  # PhantomJS doesn't support createShadowRoot, so guard against its non-existance.
  _shadowDOM = highlightedFrameElement.createShadowRoot?() ? highlightedFrameElement

  # Inject stylesheet.
  _styleSheet = DomUtils.createElement "style"
  _styleSheet.innerHTML = "@import url(\"#{chrome.runtime.getURL("content_scripts/vimium.css")}\");"
  _shadowDOM.appendChild _styleSheet

  _frameEl = DomUtils.createElement "div"
  _frameEl.className = "vimiumReset vimiumHighlightedFrame"
  _shadowDOM.appendChild _frameEl

  flashFrame = ->
    document.documentElement.appendChild highlightedFrameElement
    setTimeout (-> highlightedFrameElement.remove()), 200

#
# Called from the backend in order to change frame focus.
#
focusThisFrame = (request) ->
  unless request.forceFocusThisFrame
    if DomUtils.windowIsTooSmall() or document.body?.tagName.toLowerCase() == "frameset"
      # This frame is too small to focus or it's a frameset. Cancel and tell the background page to focus the
      # next frame instead.  This affects sites like Google Inbox, which have many tiny iframes. See #1317.
      chrome.runtime.sendMessage handler: "nextFrame"
      return
  window.focus()
  flashFrame() if request.highlight

extend window,
  scrollToBottom: ->
    Marks.setPreviousPosition()
    Scroller.scrollTo "y", "max"
  scrollToTop: (count) ->
    Marks.setPreviousPosition()
    Scroller.scrollTo "y", (count - 1) * Settings.get("scrollStepSize")
  scrollToLeft: -> Scroller.scrollTo "x", 0
  scrollToRight: -> Scroller.scrollTo "x", "max"
  scrollUp: (count) -> Scroller.scrollBy "y", -1 * Settings.get("scrollStepSize") * count
  scrollDown: (count) -> Scroller.scrollBy "y", Settings.get("scrollStepSize") * count
  scrollPageUp: (count) -> Scroller.scrollBy "y", "viewSize", -1/2 * count
  scrollPageDown: (count) -> Scroller.scrollBy "y", "viewSize", 1/2 * count
  scrollFullPageUp: (count) -> Scroller.scrollBy "y", "viewSize", -1 * count
  scrollFullPageDown: (count) -> Scroller.scrollBy "y", "viewSize", 1 * count
  scrollLeft: (count) -> Scroller.scrollBy "x", -1 * Settings.get("scrollStepSize") * count
  scrollRight: (count) -> Scroller.scrollBy "x", Settings.get("scrollStepSize") * count

extend window,
  reload: -> window.location.reload()
  goBack: (count) -> history.go(-count)
  goForward: (count) -> history.go(count)

  goUp: (count) ->
    url = window.location.href
    if (url[url.length - 1] == "/")
      url = url.substring(0, url.length - 1)

    urlsplit = url.split("/")
    # make sure we haven't hit the base domain yet
    if (urlsplit.length > 3)
      urlsplit = urlsplit.slice(0, Math.max(3, urlsplit.length - count))
      window.location.href = urlsplit.join('/')

  goToRoot: ->
    window.location.href = window.location.origin

  mainFrame: -> focusThisFrame highlight: true, forceFocusThisFrame: true

  toggleViewSource: ->
    chrome.runtime.sendMessage { handler: "getCurrentTabUrl" }, (url) ->
      if (url.substr(0, 12) == "view-source:")
        url = url.substr(12, url.length - 12)
      else
        url = "view-source:" + url
      chrome.runtime.sendMessage {handler: "openUrlInNewTab", url}

  copyCurrentUrl: ->
    # TODO(ilya): When the following bug is fixed, revisit this approach of sending back to the background
    # page to copy.
    # http://code.google.com/p/chromium/issues/detail?id=55188
    chrome.runtime.sendMessage { handler: "getCurrentTabUrl" }, (url) ->
      chrome.runtime.sendMessage { handler: "copyToClipboard", data: url }
      url = url[0..25] + "...." if 28 < url.length
      HUD.showForDuration("Yanked #{url}", 2000)

  enterInsertMode: ->
    # If a focusable element receives the focus, then we exit and leave the permanently-installed insert-mode
    # instance to take over.
    new InsertMode global: true, exitOnFocus: true

  enterVisualMode: ->
    new VisualMode userLaunchedMode: true

  enterVisualLineMode: ->
    new VisualLineMode userLaunchedMode: true

  passNextKey: (count) ->
    new PassNextKeyMode count

  focusInput: do ->
    # Track the most recently focused input element.
    recentlyFocusedElement = null
    window.addEventListener "focus",
      (event) -> recentlyFocusedElement = event.target if DomUtils.isEditable event.target
    , true

    (count) ->
      mode = InsertMode
      # Focus the first input element on the page, and create overlays to highlight all the input elements, with
      # the currently-focused element highlighted specially. Tabbing will shift focus to the next input element.
      # Pressing any other key will remove the overlays and the special tab behavior.
      # The mode argument is the mode to enter once an input is selected.
      resultSet = DomUtils.evaluateXPath textInputXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE
      visibleInputs =
        for i in [0...resultSet.snapshotLength] by 1
          element = resultSet.snapshotItem i
          continue unless DomUtils.getVisibleClientRect element, true
          { element, rect: Rect.copy element.getBoundingClientRect() }

      if visibleInputs.length == 0
        HUD.showForDuration("There are no inputs to focus.", 1000)
        return

      # This is a hack to improve usability on the Vimium options page.  We prime the recently-focused input
      # to be the key-mappings input.  Arguably, this is the input that the user is most likely to use.
      recentlyFocusedElement ?= document.getElementById "keyMappings" if window.isVimiumOptionsPage

      selectedInputIndex =
        if count == 1
          # As the starting index, we pick that of the most recently focused input element (or 0).
          elements = visibleInputs.map (visibleInput) -> visibleInput.element
          Math.max 0, elements.indexOf recentlyFocusedElement
        else
          Math.min(count, visibleInputs.length) - 1

      hints = for tuple in visibleInputs
        hint = DomUtils.createElement "div"
        hint.className = "vimiumReset internalVimiumInputHint vimiumInputHint"

        # minus 1 for the border
        hint.style.left = (tuple.rect.left - 1) + window.scrollX + "px"
        hint.style.top = (tuple.rect.top - 1) + window.scrollY  + "px"
        hint.style.width = tuple.rect.width + "px"
        hint.style.height = tuple.rect.height + "px"

        hint

      new class FocusSelector extends Mode
        constructor: ->
          super
            name: "focus-selector"
            exitOnClick: true
            keydown: (event) =>
              if event.keyCode == KeyboardUtils.keyCodes.tab
                hints[selectedInputIndex].classList.remove 'internalVimiumSelectedInputHint'
                selectedInputIndex += hints.length + (if event.shiftKey then -1 else 1)
                selectedInputIndex %= hints.length
                hints[selectedInputIndex].classList.add 'internalVimiumSelectedInputHint'
                DomUtils.simulateSelect visibleInputs[selectedInputIndex].element
                @suppressEvent
              else unless event.keyCode == KeyboardUtils.keyCodes.shiftKey
                @exit()
                # Give the new mode the opportunity to handle the event.
                @restartBubbling

          @hintContainingDiv = DomUtils.addElementList hints,
            id: "vimiumInputMarkerContainer"
            className: "vimiumReset"

          DomUtils.simulateSelect visibleInputs[selectedInputIndex].element
          if visibleInputs.length == 1
            @exit()
            return
          else
            hints[selectedInputIndex].classList.add 'internalVimiumSelectedInputHint'

        exit: ->
          super()
          DomUtils.removeElement @hintContainingDiv
          if mode and document.activeElement and DomUtils.isEditable document.activeElement
            new mode
              singleton: "post-find-mode/focus-input"
              targetElement: document.activeElement
              indicator: false

# Checks if Vimium should be enabled or not in this frame.  As a side effect, it also informs the background
# page whether this frame has the focus, allowing the background page to track the active frame's URL and set
# the page icon.
checkIfEnabledForUrl = do ->
  Frame.addEventListener "isEnabledForUrl", (response) ->
    {isEnabledForUrl, passKeys, frameIsFocused} = response
    initializeOnEnabledStateKnown isEnabledForUrl
    normalMode.setPassKeys passKeys
    # Hide the HUD if we're not enabled.
    HUD.hide true, false unless isEnabledForUrl

  (frameIsFocused = windowIsFocused()) ->
    Frame.postMessage "isEnabledForUrl", {frameIsFocused, url: window.location.toString()}

# When we're informed by the background page that a URL in this tab has changed, we check if we have the
# correct enabled state (but only if this frame has the focus).
checkEnabledAfterURLChange = ->
  checkIfEnabledForUrl() if windowIsFocused()

handleEscapeForFindMode = ->
  document.body.classList.remove("vimiumFindMode")
  # removing the class does not re-color existing selections. we recreate the current selection so it reverts
  # back to the default color.
  selection = window.getSelection()
  unless selection.isCollapsed
    range = window.getSelection().getRangeAt(0)
    window.getSelection().removeAllRanges()
    window.getSelection().addRange(range)
  focusFoundLink() || selectFoundInputElement()

# <esc> sends us into insert mode if possible, but <cr> does not.
# <esc> corresponds approximately to 'nevermind, I have found it already' while <cr> means 'I want to save
# this query and do more searches with it'
handleEnterForFindMode = ->
  focusFoundLink()
  document.body.classList.add("vimiumFindMode")
  FindMode.saveQuery()

focusFoundLink = ->
  if (FindMode.query.hasResults)
    link = getLinkFromSelection()
    link.focus() if link

selectFoundInputElement = ->
  # Since the last focused element might not be the one currently pointed to by find (e.g.  the current one
  # might be disabled and therefore unable to receive focus), we use the approximate heuristic of checking
  # that the last anchor node is an ancestor of our element.
  findModeAnchorNode = document.getSelection().anchorNode
  if (FindMode.query.hasResults && document.activeElement &&
      DomUtils.isSelectable(document.activeElement) &&
      DomUtils.isDOMDescendant(findModeAnchorNode, document.activeElement))
    DomUtils.simulateSelect(document.activeElement)

findAndFocus = (backwards) ->
  Marks.setPreviousPosition()
  FindMode.query.hasResults = FindMode.execute null, {backwards}

  if FindMode.query.hasResults
    focusFoundLink()
    new PostFindMode()
  else
    HUD.showForDuration("No matches for '#{FindMode.query.rawQuery}'", 1000)

performFind = (count) -> findAndFocus false for [0...count] by 1
performBackwardsFind = (count) -> findAndFocus true for [0...count] by 1

getLinkFromSelection = ->
  node = window.getSelection().anchorNode
  while (node && node != document.body)
    return node if (node.nodeName.toLowerCase() == "a")
    node = node.parentNode
  null

# used by the findAndFollow* functions.
followLink = (linkElement) ->
  if (linkElement.nodeName.toLowerCase() == "link")
    window.location.href = linkElement.href
  else
    # if we can click on it, don't simply set location.href: some next/prev links are meant to trigger AJAX
    # calls, like the 'more' button on GitHub's newsfeed.
    linkElement.scrollIntoView()
    DomUtils.simulateClick(linkElement)

#
# Find and follow a link which matches any one of a list of strings. If there are multiple such links, they
# are prioritized for shortness, by their position in :linkStrings, how far down the page they are located,
# and finally by whether the match is exact. Practically speaking, this means we favor 'next page' over 'the
# next big thing', and 'more' over 'nextcompany', even if 'next' occurs before 'more' in :linkStrings.
#
findAndFollowLink = (linkStrings) ->
  linksXPath = DomUtils.makeXPath(["a", "*[@onclick or @role='link' or contains(@class, 'button')]"])
  links = DomUtils.evaluateXPath(linksXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE)
  candidateLinks = []

  # at the end of this loop, candidateLinks will contain all visible links that match our patterns
  # links lower in the page are more likely to be the ones we want, so we loop through the snapshot backwards
  for i in [(links.snapshotLength - 1)..0] by -1
    link = links.snapshotItem(i)

    # ensure link is visible (we don't mind if it is scrolled offscreen)
    boundingClientRect = link.getBoundingClientRect()
    if (boundingClientRect.width == 0 || boundingClientRect.height == 0)
      continue
    computedStyle = window.getComputedStyle(link, null)
    if (computedStyle.getPropertyValue("visibility") != "visible" ||
        computedStyle.getPropertyValue("display") == "none")
      continue

    linkMatches = false
    for linkString in linkStrings
      if link.innerText.toLowerCase().indexOf(linkString) != -1 ||
          0 <= link.value?.indexOf? linkString
        linkMatches = true
        break
    continue unless linkMatches

    candidateLinks.push(link)

  return if (candidateLinks.length == 0)

  for link in candidateLinks
    link.wordCount = link.innerText.trim().split(/\s+/).length

  # We can use this trick to ensure that Array.sort is stable. We need this property to retain the reverse
  # in-page order of the links.

  candidateLinks.forEach((a,i) -> a.originalIndex = i)

  # favor shorter links, and ignore those that are more than one word longer than the shortest link
  candidateLinks =
    candidateLinks
      .sort((a, b) ->
        if (a.wordCount == b.wordCount) then a.originalIndex - b.originalIndex else a.wordCount - b.wordCount
      )
      .filter((a) -> a.wordCount <= candidateLinks[0].wordCount + 1)

  for linkString in linkStrings
    exactWordRegex =
      if /\b/.test(linkString[0]) or /\b/.test(linkString[linkString.length - 1])
        new RegExp "\\b" + linkString + "\\b", "i"
      else
        new RegExp linkString, "i"
    for candidateLink in candidateLinks
      if exactWordRegex.test(candidateLink.innerText) ||
          (candidateLink.value && exactWordRegex.test(candidateLink.value))
        followLink(candidateLink)
        return true
  false

findAndFollowRel = (value) ->
  relTags = ["link", "a", "area"]
  for tag in relTags
    elements = document.getElementsByTagName(tag)
    for element in elements
      if (element.hasAttribute("rel") && element.rel.toLowerCase() == value)
        followLink(element)
        return true

window.goPrevious = ->
  previousPatterns = Settings.get("previousPatterns") || ""
  previousStrings = previousPatterns.split(",").filter( (s) -> s.trim().length )
  findAndFollowRel("prev") || findAndFollowLink(previousStrings)

window.goNext = ->
  nextPatterns = Settings.get("nextPatterns") || ""
  nextStrings = nextPatterns.split(",").filter( (s) -> s.trim().length )
  findAndFollowRel("next") || findAndFollowLink(nextStrings)

# Enters find mode.  Returns the new find-mode instance.
enterFindMode = ->
  Marks.setPreviousPosition()
  new FindMode()

window.showHelp = (sourceFrameId) ->
  chrome.runtime.sendMessage handler: "getHelpDialogHtml", (response) ->
    HelpDialog.toggle {sourceFrameId, html: response}

# If we are in the help dialog iframe, then HelpDialog is already defined with the necessary functions.
window.HelpDialog ?=
  helpUI: null
  isShowing: -> @helpUI?.showing
  abort: -> @helpUI.hide false if @isShowing()

  toggle: (request) ->
    DomUtils.documentComplete =>
      @helpUI ?= new UIComponent "pages/help_dialog.html", "vimiumHelpDialogFrame", ->
    if @helpUI? and @isShowing()
      @helpUI.hide()
    else if @helpUI?
      @helpUI.activate extend request,
        name: "activate", focus: true

initializePreDomReady()
DomUtils.documentReady initializeOnDomReady

root = exports ? window
root.handlerStack = handlerStack
root.frameId = frameId
root.Frame = Frame
root.windowIsFocused = windowIsFocused
root.bgLog = bgLog
# These are exported for find mode and link-hints mode.
extend root, {handleEscapeForFindMode, handleEnterForFindMode, performFind, performBackwardsFind,
  enterFindMode, focusThisFrame}
# These are exported only for the tests.
extend root, {installModes, installListeners}

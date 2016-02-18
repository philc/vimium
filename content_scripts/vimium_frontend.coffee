#
# This content script takes input from its webpage and executes commands locally on behalf of the background
# page. It must be run prior to domReady so that we perform some operations very early. We tell the
# background page that we're in domReady and ready to accept normal commands by connectiong to a port named
# "domReady".
#

keyPort = null
isEnabledForUrl = true
isIncognitoMode = chrome.extension.inIncognitoContext
passKeys = null
keyQueue = null
# The user's operating system.
currentCompletionKeys = ""
validFirstKeys = ""

# We track whther the current window has the focus or not.
windowIsFocused = do ->
  windowHasFocus = document.hasFocus()
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

#
# Give this frame a unique (non-zero) id.
#
frameId = 1 + Math.floor(Math.random()*999999999)

# For debugging only. This logs to the console on the background page.
bgLog = (args...) ->
  args = (arg.toString() for arg in args)
  chrome.runtime.sendMessage handler: "log", frameId: frameId, message: args.join " "

# If an input grabs the focus before the user has interacted with the page, then grab it back (if the
# grabBackFocus option is set).
class GrabBackFocus extends Mode
  constructor: ->
    super
      name: "grab-back-focus"
      keydown: => @alwaysContinueBubbling => @exit()

    @push
      _name: "grab-back-focus-mousedown"
      mousedown: => @alwaysContinueBubbling => @exit()

    Settings.use "grabBackFocus", (grabBackFocus) =>
      if grabBackFocus
        @push
          _name: "grab-back-focus-focus"
          focus: (event) => @grabBackFocus event.target
        # An input may already be focused. If so, grab back the focus.
        @grabBackFocus document.activeElement if document.activeElement
      else
        @exit()

  grabBackFocus: (element) ->
    return @continueBubbling unless DomUtils.isEditable element
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

# Only exported for tests.
window.initializeModes = ->
  class NormalMode extends Mode
    constructor: ->
      super
        name: "normal"
        indicator: false # There is no mode indicator in normal mode.
        keydown: (event) => onKeydown.call @, event
        keypress: (event) => onKeypress.call @, event
        keyup: (event) => onKeyup.call @, event

  # Install the permanent modes.  The permanently-installed insert mode tracks focus/blur events, and
  # activates/deactivates itself accordingly.
  new NormalMode
  new PassKeysMode
  new InsertMode permanent: true
  Scroller.init()

#
# Complete initialization work that sould be done prior to DOMReady.
#
initializePreDomReady = ->
  checkIfEnabledForUrl()
  refreshCompletionKeys()

  # Send the key to the key handler in the background page.
  keyPort = chrome.runtime.connect({ name: "keyDown" })
  # If the port is closed, the background page has gone away (since we never close it ourselves). Disable all
  # our event listeners, and stub out chrome.runtime.sendMessage/connect (to prevent errors).
  # TODO(mrmr1993): Do some actual cleanup to free resources, hide UI, etc.
  keyPort.onDisconnect.addListener ->
    isEnabledForUrl = false
    chrome.runtime.sendMessage = ->
    chrome.runtime.connect = ->
    window.removeEventListener "focus", onFocus

  requestHandlers =
    showHUDforDuration: handleShowHUDforDuration
    toggleHelpDialog: (request) -> if frameId == request.frameId then HelpDialog.toggle request.dialogHtml
    focusFrame: (request) -> if (frameId == request.frameId) then focusThisFrame request
    refreshCompletionKeys: refreshCompletionKeys
    getScrollPosition: -> scrollX: window.scrollX, scrollY: window.scrollY
    setScrollPosition: setScrollPosition
    executePageCommand: executePageCommand
    currentKeyQueue: (request) ->
      keyQueue = request.keyQueue
      handlerStack.bubbleEvent "registerKeyQueue", { keyQueue: keyQueue }
    # A frame has received the focus.  We don't care here (the Vomnibar/UI-component handles this).
    frameFocused: ->
    checkEnabledAfterURLChange: checkEnabledAfterURLChange

  chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
    # In the options page, we will receive requests from both content and background scripts. ignore those
    # from the former.
    return if sender.tab and not sender.tab.url.startsWith 'chrome-extension://'
    # These requests are delivered to the options page, but there are no handlers there.
    return if request.handler in [ "registerFrame", "frameFocused", "unregisterFrame", "setIcon" ]
    shouldHandleRequest = isEnabledForUrl
    # We always handle the message if it's one of these listed message types.
    shouldHandleRequest ||= request.name in [ "executePageCommand", "checkEnabledAfterURLChange" ]
    # Requests with a frameId of zero should always and only be handled in the main/top frame (regardless of
    # whether Vimium is enabled there).
    if request.frameId == 0 and DomUtils.isTopFrame()
      request.frameId = frameId
      shouldHandleRequest = true
    sendResponse requestHandlers[request.name](request, sender) if shouldHandleRequest
    # Ensure the sendResponse callback is freed.
    false

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
installedListeners = false
window.installListeners = ->
  unless installedListeners
    initializeModes()
    # Key event handlers fire on window before they do on document. Prefer window for key events so the page
    # can't set handlers to grab the keys before us.
    for type in [ "keydown", "keypress", "keyup", "click", "focus", "blur", "mousedown", "scroll" ]
      do (type) -> installListener window, type, (event) -> handlerStack.bubbleEvent type, event
    installListener document, "DOMActivate", (event) -> handlerStack.bubbleEvent 'DOMActivate', event
    installedListeners = true
    # Other once-only initialisation.
    FindModeHistory.init()
    new GrabBackFocus if isEnabledForUrl

#
# Whenever we get the focus:
# - Tell the background page this frame's URL.
# - Check if we should be enabled.
#
onFocus = (event) ->
  if event.target == window
    chrome.runtime.sendMessage handler: "frameFocused", frameId: frameId
    checkIfEnabledForUrl true

# We install these listeners directly (that is, we don't use installListener) because we still need to receive
# events when Vimium is not enabled.
window.addEventListener "focus", onFocus
window.addEventListener "hashchange", onFocus

#
# Initialization tasks that must wait for the document to be ready.
#
initializeOnDomReady = ->
  # Tell the background page we're in the dom ready state.
  chrome.runtime.connect({ name: "domReady" })
  # We only initialize the vomnibar in the tab's main frame, because it's only ever opened there.
  Vomnibar.init() if DomUtils.isTopFrame()
  HUD.init()

registerFrame = ->
  # Don't register frameset containers; focusing them is no use.
  unless document.body?.tagName.toLowerCase() == "frameset"
    chrome.runtime.sendMessage
      handler: "registerFrame"
      frameId: frameId

# Unregister the frame if we're going to exit.
unregisterFrame = ->
  chrome.runtime.sendMessage
    handler: "unregisterFrame"
    frameId: frameId
    tab_is_closing: DomUtils.isTopFrame()

executePageCommand = (request) ->
  commandType = request.command.split(".")[0]
  # Vomnibar commands are handled in the tab's main/top frame.  They are handled even if Vimium is otherwise
  # disabled in the frame.
  if commandType == "Vomnibar"
    if DomUtils.isTopFrame()
      # We pass the frameId from request.  That's the frame which originated the request, so that's the frame
      # which should receive the focus when the vomnibar closes.
      Utils.invokeCommandString request.command, [ request.frameId, request.registryEntry ]
      refreshCompletionKeys request
    return

  # All other commands are handled in their frame (but only if Vimium is enabled).
  return unless frameId == request.frameId and isEnabledForUrl

  if request.registryEntry.passCountToFunction
    Utils.invokeCommandString(request.command, [request.count])
  else
    Utils.invokeCommandString(request.command) for i in [0...request.count]

  refreshCompletionKeys(request)

handleShowHUDforDuration = ({ text, duration }) ->
  if DomUtils.isTopFrame()
    DomUtils.documentReady -> HUD.showForDuration text, duration

setScrollPosition = ({ scrollX, scrollY }) ->
  if DomUtils.isTopFrame()
    DomUtils.documentReady ->
      window.focus()
      document.body.focus()
      if 0 < scrollX or 0 < scrollY
        Marks.setPreviousPosition()
        window.scrollTo scrollX, scrollY

#
# Called from the backend in order to change frame focus.
#
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

  window.focusThisFrame = (request) ->
    if window.innerWidth < 3 or window.innerHeight < 3
      # This frame is too small to focus. Cancel and tell the background frame to focus the next one instead.
      # This affects sites like Google Inbox, which have many tiny iframes. See #1317.
      # Here we're assuming that there is at least one frame large enough to focus.
      chrome.runtime.sendMessage({ handler: "nextFrame", frameId: frameId })
      return
    window.focus()
    shouldHighlight = request.highlight
    shouldHighlight ||= request.highlightOnlyIfNotTop and not DomUtils.isTopFrame()
    if shouldHighlight
      document.documentElement.appendChild highlightedFrameElement
      setTimeout (-> highlightedFrameElement.remove()), 200

window.focusThisFrame = ->

extend window,
  scrollToBottom: ->
    Marks.setPreviousPosition()
    Scroller.scrollTo "y", "max"
  scrollToTop: (count) ->
    Marks.setPreviousPosition()
    Scroller.scrollTo "y", (count - 1) * Settings.get("scrollStepSize")
  scrollToLeft: -> Scroller.scrollTo "x", 0
  scrollToRight: -> Scroller.scrollTo "x", "max"
  scrollUp: -> Scroller.scrollBy "y", -1 * Settings.get("scrollStepSize")
  scrollDown: -> Scroller.scrollBy "y", Settings.get("scrollStepSize")
  scrollPageUp: -> Scroller.scrollBy "y", "viewSize", -1/2
  scrollPageDown: -> Scroller.scrollBy "y", "viewSize", 1/2
  scrollFullPageUp: -> Scroller.scrollBy "y", "viewSize", -1
  scrollFullPageDown: -> Scroller.scrollBy "y", "viewSize"
  scrollLeft: -> Scroller.scrollBy "x", -1 * Settings.get("scrollStepSize")
  scrollRight: -> Scroller.scrollBy "x", Settings.get("scrollStepSize")

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

  goToRoot: () ->
    window.location.href = window.location.origin

  toggleViewSource: ->
    chrome.runtime.sendMessage { handler: "getCurrentTabUrl" }, (url) ->
      if (url.substr(0, 12) == "view-source:")
        url = url.substr(12, url.length - 12)
      else
        url = "view-source:" + url
      chrome.runtime.sendMessage({ handler: "openUrlInNewTab", url: url, selected: true })

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
    new VisualMode()

  enterVisualLineMode: ->
    new VisualLineMode

  passNextKey: (count) ->
    new PassNextKeyMode count

  focusInput: do ->
    # Track the most recently focused input element.
    recentlyFocusedElement = null
    window.addEventListener "focus",
      (event) -> recentlyFocusedElement = event.target if DomUtils.isEditable event.target
    , true

    (count, mode = InsertMode) ->
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
                # Deactivate any active modes on this element (PostFindMode, or a suspended edit mode).
                @deactivateSingleton visibleInputs[selectedInputIndex].element
                DomUtils.simulateSelect visibleInputs[selectedInputIndex].element
                @suppressEvent
              else unless event.keyCode == KeyboardUtils.keyCodes.shiftKey
                @exit()
                # Give the new mode the opportunity to handle the event.
                @restartBubbling

          @hintContainingDiv = DomUtils.addElementList hints,
            id: "vimiumInputMarkerContainer"
            className: "vimiumReset"

          # Deactivate any active modes on this element (PostFindMode, or a suspended edit mode).
          @deactivateSingleton visibleInputs[selectedInputIndex].element
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
              singleton: document.activeElement
              targetElement: document.activeElement
              indicator: false

# Track which keydown events we have handled, so that we can subsequently suppress the corresponding keyup
# event.
KeydownEvents =
  handledEvents: {}

  getEventCode: (event) -> event.keyCode

  push: (event) ->
    @handledEvents[@getEventCode event] = true

  # Yields truthy or falsy depending upon whether a corresponding keydown event is present (and removes that
  # event).
  pop: (event) ->
    detailString = @getEventCode event
    value = @handledEvents[detailString]
    delete @handledEvents[detailString]
    value

  clear: -> @handledEvents = {}

handlerStack.push
  _name: "KeydownEvents-cleanup"
  blur: (event) -> KeydownEvents.clear() if event.target == window; true

#
# Sends everything except i & ESC to the handler in background_page. i & ESC are special because they control
# insert mode which is local state to the page. The key will be are either a single ascii letter or a
# key-modifier pair, e.g. <c-a> for control a.
#
# Note that some keys will only register keydown events and not keystroke events, e.g. ESC.
#
# @/this, here, is the the normal-mode Mode object.
onKeypress = (event) ->
  keyChar = KeyboardUtils.getKeyCharString event
  if keyChar
    if currentCompletionKeys.indexOf(keyChar) != -1 or isValidFirstKey keyChar
      DomUtils.suppressEvent(event)
      keyPort.postMessage keyChar:keyChar, frameId:frameId
      return @stopBubblingAndTrue

    keyPort.postMessage keyChar:keyChar, frameId:frameId

  return @continueBubbling

# @/this, here, is the the normal-mode Mode object.
onKeydown = (event) ->
  keyChar = KeyboardUtils.getKeyCharString event

  if (HelpDialog.showing && KeyboardUtils.isEscape(event))
    HelpDialog.hide()
    DomUtils.suppressEvent event
    KeydownEvents.push event
    return @stopBubblingAndTrue

  else
    if (keyChar)
      if (currentCompletionKeys.indexOf(keyChar) != -1 or isValidFirstKey(keyChar))
        DomUtils.suppressEvent event
        KeydownEvents.push event
        keyPort.postMessage({ keyChar:keyChar, frameId:frameId })
        return @stopBubblingAndTrue

      keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

    else if (KeyboardUtils.isEscape(event))
      keyPort.postMessage({ keyChar:"<ESC>", frameId:frameId })

  # Added to prevent propagating this event to other listeners if it's one that'll trigger a Vimium command.
  # The goal is to avoid the scenario where Google Instant Search uses every keydown event to dump us
  # back into the search box. As a side effect, this should also prevent overriding by other sites.
  #
  # Subject to internationalization issues since we're using keyIdentifier instead of charCode (in keypress).
  #
  # TOOD(ilya): Revisit this. Not sure it's the absolute best approach.
  if not keyChar &&
     (currentCompletionKeys.indexOf(KeyboardUtils.getKeyChar(event)) != -1 ||
      isValidFirstKey(KeyboardUtils.getKeyChar(event)))
    DomUtils.suppressPropagation(event)
    KeydownEvents.push event
    return @stopBubblingAndTrue

  return @continueBubbling

# @/this, here, is the the normal-mode Mode object.
onKeyup = (event) ->
  return @continueBubbling unless KeydownEvents.pop event
  DomUtils.suppressPropagation(event)
  @stopBubblingAndTrue

# Checks if Vimium should be enabled or not in this frame.  As a side effect, it also informs the background
# page whether this frame has the focus, allowing the background page to track the active frame's URL.
checkIfEnabledForUrl = (frameIsFocused = windowIsFocused()) ->
  url = window.location.toString()
  chrome.runtime.sendMessage { handler: "isEnabledForUrl", url: url, frameIsFocused: frameIsFocused }, (response) ->
    { isEnabledForUrl, passKeys } = response
    installListeners() # But only if they have not been installed already.
    if HUD.isReady() and not isEnabledForUrl
      # Quickly hide any HUD we might already be showing, e.g. if we entered insert mode on page load.
      HUD.hide()
    handlerStack.bubbleEvent "registerStateChange",
      enabled: isEnabledForUrl
      passKeys: passKeys
    # Update the page icon, if necessary.
    if windowIsFocused()
      chrome.runtime.sendMessage
        handler: "setIcon"
        icon:
          if isEnabledForUrl and not passKeys then "enabled"
          else if isEnabledForUrl then "partial"
          else "disabled"
    null

# When we're informed by the background page that a URL in this tab has changed, we check if we have the
# correct enabled state (but only if this frame has the focus).
checkEnabledAfterURLChange = ->
  checkIfEnabledForUrl() if windowIsFocused()

# Exported to window, but only for DOM tests.
window.refreshCompletionKeys = (response) ->
  if (response)
    currentCompletionKeys = response.completionKeys

    if (response.validFirstKeys)
      validFirstKeys = response.validFirstKeys
  else
    chrome.runtime.sendMessage({ handler: "getCompletionKeys" }, refreshCompletionKeys)

isValidFirstKey = (keyChar) ->
  validFirstKeys[keyChar] || /^[1-9]/.test(keyChar)

window.handleEscapeForFindMode = ->
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
window.handleEnterForFindMode = ->
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

window.performFind = -> findAndFocus()

window.performBackwardsFind = -> findAndFocus(true)

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
    linkElement.focus()
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
      if (link.innerText.toLowerCase().indexOf(linkString) != -1)
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
      if (exactWordRegex.test(candidateLink.innerText))
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
window.enterFindMode = ->
  Marks.setPreviousPosition()
  new FindMode()

# If we are in the help dialog iframe, HelpDialog is already defined with the necessary functions.
window.HelpDialog ?=
  helpUI: null
  container: null
  showing: false

  init: ->
    return if @helpUI?

    @helpUI = new UIComponent "pages/help_dialog.html", "vimiumHelpDialogFrame", (event) =>
      @hide() if event.data == "hide"

  isReady: -> @helpUI?

  show: (html) ->
    @init()
    return if @showing or !@isReady()
    @showing = true
    @helpUI.activate html

  hide: ->
    @showing = false
    @helpUI.hide()

  toggle: (html) ->
    if @showing then @hide() else @show html

initializePreDomReady()
DomUtils.documentReady initializeOnDomReady
DomUtils.documentReady registerFrame
window.addEventListener "unload", unregisterFrame

window.onbeforeunload = ->
  chrome.runtime.sendMessage(
    handler: "updateScrollPosition"
    scrollX: window.scrollX
    scrollY: window.scrollY)

root = exports ? window
root.handlerStack = handlerStack
root.frameId = frameId
root.windowIsFocused = windowIsFocused
root.bgLog = bgLog

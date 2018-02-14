class NormalMode extends KeyHandlerMode
  constructor: (options = {}) ->
    defaults =
      name: "normal"
      indicator: false # There is normally no mode indicator in normal mode.
      commandHandler: @commandHandler.bind this

    super extend defaults, options

    chrome.storage.local.get "normalModeKeyStateMapping", (items) =>
      @setKeyMapping items.normalModeKeyStateMapping

    chrome.storage.onChanged.addListener (changes, area) =>
      if area == "local" and changes.normalModeKeyStateMapping?.newValue
        @setKeyMapping changes.normalModeKeyStateMapping.newValue

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
      NormalModeCommands[registryEntry.command] count, {registryEntry}

enterNormalMode = (count) ->
  new NormalMode
    indicator: "Normal mode (pass keys disabled)"
    exitOnEscape: true
    singleton: "enterNormalMode"
    count: count

NormalModeCommands =
  # Scrolling.
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

  # Tab navigation: back, forward.
  goBack: (count) -> history.go(-count)
  goForward: (count) -> history.go(count)

  # Url manipulation.
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

  toggleViewSource: ->
    chrome.runtime.sendMessage { handler: "getCurrentTabUrl" }, (url) ->
      if (url.substr(0, 12) == "view-source:")
        url = url.substr(12, url.length - 12)
      else
        url = "view-source:" + url
      chrome.runtime.sendMessage {handler: "openUrlInNewTab", url}

  copyCurrentUrl: ->
    chrome.runtime.sendMessage { handler: "getCurrentTabUrl" }, (url) ->
      HUD.copyToClipboard url
      url = url[0..25] + "...." if 28 < url.length
      HUD.showForDuration("Yanked #{url}", 2000)

  openCopiedUrlInNewTab: (count) ->
    HUD.pasteFromClipboard (url) ->
      chrome.runtime.sendMessage { handler: "openUrlInNewTab", url, count }

  openCopiedUrlInCurrentTab: ->
    HUD.pasteFromClipboard (url) ->
      chrome.runtime.sendMessage { handler: "openUrlInCurrentTab", url }

  # Mode changes.
  enterInsertMode: ->
    # If a focusable element receives the focus, then we exit and leave the permanently-installed insert-mode
    # instance to take over.
    new InsertMode global: true, exitOnFocus: true

  enterVisualMode: ->
    new VisualMode userLaunchedMode: true

  enterVisualLineMode: ->
    new VisualLineMode userLaunchedMode: true

  enterFindMode: ->
    Marks.setPreviousPosition()
    new FindMode()

  # Find.
  performFind: (count) -> FindMode.findNext false for [0...count] by 1
  performBackwardsFind: (count) -> FindMode.findNext true for [0...count] by 1

  # Misc.
  mainFrame: -> focusThisFrame highlight: true, forceFocusThisFrame: true
  showHelp: (sourceFrameId) -> HelpDialog.toggle {sourceFrameId, showAllCommandDetails: false}

  passNextKey: (count, options) ->
    if options.registryEntry.options.normal
      enterNormalMode count
    else
      new PassNextKeyMode count

  goPrevious: ->
    previousPatterns = Settings.get("previousPatterns") || ""
    previousStrings = previousPatterns.split(",").filter( (s) -> s.trim().length )
    findAndFollowRel("prev") || findAndFollowLink(previousStrings)

  goNext: ->
    nextPatterns = Settings.get("nextPatterns") || ""
    nextStrings = nextPatterns.split(",").filter( (s) -> s.trim().length )
    findAndFollowRel("next") || findAndFollowLink(nextStrings)

  focusInput: (count) ->
    # Focus the first input element on the page, and create overlays to highlight all the input elements, with
    # the currently-focused element highlighted specially. Tabbing will shift focus to the next input element.
    # Pressing any other key will remove the overlays and the special tab behavior.
    resultSet = DomUtils.evaluateXPath textInputXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE
    visibleInputs =
      for i in [0...resultSet.snapshotLength] by 1
        element = resultSet.snapshotItem i
        continue unless DomUtils.getVisibleClientRect element, true
        { element, index: i, rect: Rect.copy element.getBoundingClientRect() }

    visibleInputs.sort ({element: element1, index: i1}, {element: element2, index: i2}) ->
      # Put elements with a lower positive tabIndex first, keeping elements in DOM order.
      if element1.tabIndex > 0
        if element2.tabIndex > 0
          tabDifference = element1.tabIndex - element2.tabIndex
          if tabDifference != 0
            tabDifference
          else
            i1 - i2
        else
          -1
      else if element2.tabIndex > 0
        1
      else
        i1 - i2

    if visibleInputs.length == 0
      HUD.showForDuration("There are no inputs to focus.", 1000)
      return

    # This is a hack to improve usability on the Vimium options page.  We prime the recently-focused input
    # to be the key-mappings input.  Arguably, this is the input that the user is most likely to use.
    recentlyFocusedElement = lastFocusedInput()

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

    new FocusSelector hints, visibleInputs, selectedInputIndex

if LinkHints?
  extend NormalModeCommands,
    "LinkHints.activateMode": LinkHints.activateMode.bind LinkHints
    "LinkHints.activateModeToOpenInNewTab": LinkHints.activateModeToOpenInNewTab.bind LinkHints
    "LinkHints.activateModeToOpenInNewForegroundTab": LinkHints.activateModeToOpenInNewForegroundTab.bind LinkHints
    "LinkHints.activateModeWithQueue": LinkHints.activateModeWithQueue.bind LinkHints
    "LinkHints.activateModeToOpenIncognito": LinkHints.activateModeToOpenIncognito.bind LinkHints
    "LinkHints.activateModeToDownloadLink": LinkHints.activateModeToDownloadLink.bind LinkHints
    "LinkHints.activateModeToCopyLinkUrl": LinkHints.activateModeToCopyLinkUrl.bind LinkHints

if Vomnibar?
  extend NormalModeCommands,
    "Vomnibar.activate": Vomnibar.activate.bind Vomnibar
    "Vomnibar.activateInNewTab": Vomnibar.activateInNewTab.bind Vomnibar
    "Vomnibar.activateTabSelection": Vomnibar.activateTabSelection.bind Vomnibar
    "Vomnibar.activateBookmarks": Vomnibar.activateBookmarks.bind Vomnibar
    "Vomnibar.activateBookmarksInNewTab": Vomnibar.activateBookmarksInNewTab.bind Vomnibar
    "Vomnibar.activateEditUrl": Vomnibar.activateEditUrl.bind Vomnibar
    "Vomnibar.activateEditUrlInNewTab": Vomnibar.activateEditUrlInNewTab.bind Vomnibar

if Marks?
  extend NormalModeCommands,
    "Marks.activateCreateMode": Marks.activateCreateMode.bind Marks
    "Marks.activateGotoMode": Marks.activateGotoMode.bind Marks

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
  DomUtils?.makeXPath(inputElements)
)()

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

class FocusSelector extends Mode
  constructor: (hints, visibleInputs, selectedInputIndex) ->
    super
      name: "focus-selector"
      exitOnClick: true
      keydown: (event) =>
        if event.key == "Tab"
          hints[selectedInputIndex].classList.remove 'internalVimiumSelectedInputHint'
          selectedInputIndex += hints.length + (if event.shiftKey then -1 else 1)
          selectedInputIndex %= hints.length
          hints[selectedInputIndex].classList.add 'internalVimiumSelectedInputHint'
          DomUtils.simulateSelect visibleInputs[selectedInputIndex].element
          @suppressEvent
        else unless event.key == "Shift"
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
    if document.activeElement and DomUtils.isEditable document.activeElement
      new InsertMode
        singleton: "post-find-mode/focus-input"
        targetElement: document.activeElement
        indicator: false

root = exports ? (window.root ?= {})
root.NormalMode = NormalMode
root.NormalModeCommands = NormalModeCommands
extend window, root unless exports?

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
      Utils.invokeCommandString registryEntry.command, count, {registryEntry}

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

  # Page state.
  reload: (count, options) ->
    hard = options.registryEntry.options.hard ? false
    window.location.reload(hard)
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
      chrome.runtime.sendMessage { handler: "copyToClipboard", data: url }
      url = url[0..25] + "...." if 28 < url.length
      HUD.showForDuration("Yanked #{url}", 2000)

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

  focusInput: (count) ->
    # Focus the first input element on the page, and create overlays to highlight all the input elements, with
    # the currently-focused element highlighted specially. Tabbing will shift focus to the next input element.
    # Pressing any other key will remove the overlays and the special tab behavior.
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
    recentlyFocusedElement = lastFocusedInput()
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

    new FocusSelector hints, visibleInputs, selectedInputIndex

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

root = exports ? (window.root ?= {})
root.NormalMode = NormalMode
root.NormalModeCommands = NormalModeCommands
extend root, NormalModeCommands
extend window, root unless exports?

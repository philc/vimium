#
# This content script takes input from its webpage and executes commands locally on behalf of the background
# page. It must be run prior to domReady so that we perform some operations very early. We tell the
# background page that we're in domReady and ready to accept normal commands by connectiong to a port named
# "domReady".
#
insertModeLock = null
findMode = false
findModeQuery = { rawQuery: "" }
findModeQueryHasResults = false
findModeAnchorNode = null
isShowingHelpDialog = false
handlerStack = new HandlerStack
keyPort = null
# Users can disable Vimium on URL patterns via the settings page.
isEnabledForUrl = true
# The user's operating system.
currentCompletionKeys = null
validFirstKeys = null
activatedElement = null
passkeys = null


# The types in <input type="..."> that we consider for focusInput command. Right now this is recalculated in
# each content script. Alternatively we could calculate it once in the background page and use a request to
# fetch it each time.
# Should we include the HTML5 date pickers here?

# The corresponding XPath for such elements.
textInputXPath = (->
  textInputTypes = ["text", "search", "email", "url", "number", "password"]
  inputElements = ["input[" +
    "(" + textInputTypes.map((type) -> '@type="' + type + '"').join(" or ") + "or not(@type))" +
    " and not(@disabled or @readonly)]",
    "textarea", "*[@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"]
  DomUtils.makeXPath(inputElements)
)()

#
# settings provides a browser-global localStorage-backed dict. get() and set() are synchronous, but load()
# must be called beforehand to ensure get() will return up-to-date values.
#
settings =
  port: null
  values: {}
  loadedValues: 0
  valuesToLoad: ["scrollStepSize", "linkHintCharacters", "filterLinkHints", "hideHud", "previousPatterns",
      "nextPatterns", "findModeRawQuery", "regexFindMode", "userDefinedLinkHintCss",
      "helpDialog_showAdvancedCommands"]
  isLoaded: false
  eventListeners: {}

  init: ->
    @port = chrome.extension.connect({ name: "settings" })
    @port.onMessage.addListener(@receiveMessage)

  get: (key) -> @values[key]

  set: (key, value) ->
    @init() unless @port

    @values[key] = value
    @port.postMessage({ operation: "set", key: key, value: value })

  load: ->
    @init() unless @port

    for i of @valuesToLoad
      @port.postMessage({ operation: "get", key: @valuesToLoad[i] })

  receiveMessage: (args) ->
    # not using 'this' due to issues with binding on callback
    settings.values[args.key] = args.value
    # since load() can be called more than once, loadedValues can be greater than valuesToLoad, but we test
    # for equality so initializeOnReady only runs once
    if (++settings.loadedValues == settings.valuesToLoad.length)
      settings.isLoaded = true
      listener = null
      while (listener = settings.eventListeners["load"].pop())
        listener()

  addEventListener: (eventName, callback) ->
    if (!(eventName of @eventListeners))
      @eventListeners[eventName] = []
    @eventListeners[eventName].push(callback)

#
# Give this frame a unique id.
#
frameId = Math.floor(Math.random()*999999999)

hasModifiersRegex = /^<([amc]-)+.>/

#
# Complete initialization work that sould be done prior to DOMReady.
#
initializePreDomReady = ->
  settings.addEventListener("load", LinkHints.init.bind(LinkHints))
  settings.load()

  checkIfEnabledForUrl()

  refreshCompletionKeys()

  # Send the key to the key handler in the background page.
  keyPort = chrome.extension.connect({ name: "keyDown" })

  requestHandlers =
    hideUpgradeNotification: -> HUD.hideUpgradeNotification()
    showUpgradeNotification: (request) -> HUD.showUpgradeNotification(request.version)
    toggleHelpDialog: (request) -> toggleHelpDialog(request.dialogHtml, request.frameId)
    focusFrame: (request) -> if (frameId == request.frameId) then focusThisFrame(request.highlight)
    refreshCompletionKeys: refreshCompletionKeys
    getScrollPosition: -> scrollX: window.scrollX, scrollY: window.scrollY
    setScrollPosition: (request) -> setScrollPosition request.scrollX, request.scrollY
    executePageCommand: executePageCommand
    getActiveState: -> { enabled: isEnabledForUrl }
    disableVimium: disableVimium

  chrome.extension.onRequest.addListener (request, sender, sendResponse) ->
    # in the options page, we will receive requests from both content and background scripts. ignore those
    # from the former.
    return unless sender.tab?.url.startsWith 'chrome-extension://'
    return unless isEnabledForUrl or request.name == 'getActiveState'
    sendResponse requestHandlers[request.name](request, sender)
    # Ensure the sendResponse callback is freed.
    false

#
# This is called once the background page has told us that Vimium should be enabled for the current URL.
#
initializeWhenEnabled = (response) ->
  document.addEventListener("keydown", onKeydown, true)
  document.addEventListener("keypress", onKeypress, true)
  document.addEventListener("keyup", onKeyup, true)
  document.addEventListener("focus", onFocusCapturePhase, true)
  document.addEventListener("blur", onBlurCapturePhase, true)
  document.addEventListener("DOMActivate", onDOMActivate, true)
  enterInsertModeIfElementIsFocused()
  passkeys = response.passkeys

#
# Used to disable Vimium without needing to reload the page.
# This is called if the current page's url is blacklisted using the popup UI.
#
disableVimium = ->
  document.removeEventListener("keydown", onKeydown, true)
  document.removeEventListener("keypress", onKeypress, true)
  document.removeEventListener("keyup", onKeyup, true)
  document.removeEventListener("focus", onFocusCapturePhase, true)
  document.removeEventListener("blur", onBlurCapturePhase, true)
  document.removeEventListener("DOMActivate", onDOMActivate, true)
  isEnabledForUrl = false

#
# The backend needs to know which frame has focus.
#
window.addEventListener "focus", ->
  # settings may have changed since the frame last had focus
  settings.load()
  chrome.extension.sendRequest({ handler: "frameFocused", frameId: frameId })

#
# Initialization tasks that must wait for the document to be ready.
#
initializeOnDomReady = ->
  registerFrameIfSizeAvailable(window.top == window.self)

  enterInsertModeIfElementIsFocused() if isEnabledForUrl

  # Tell the background page we're in the dom ready state.
  chrome.extension.connect({ name: "domReady" })

# This is a little hacky but sometimes the size wasn't available on domReady?
registerFrameIfSizeAvailable = (is_top) ->
  if (innerWidth != undefined && innerWidth != 0 && innerHeight != undefined && innerHeight != 0)
    chrome.extension.sendRequest(
      handler: "registerFrame"
      frameId: frameId
      area: innerWidth * innerHeight
      is_top: is_top
      total: frames.length + 1)
  else
    setTimeout((-> registerFrameIfSizeAvailable(is_top)), 100)

#
# Enters insert mode if the currently focused element in the DOM is focusable.
#
enterInsertModeIfElementIsFocused = ->
  if (document.activeElement && isEditable(document.activeElement) && !findMode)
    enterInsertModeWithoutShowingIndicator(document.activeElement)

onDOMActivate = (event) -> activatedElement = event.target

executePageCommand = (request) ->
  return unless frameId == request.frameId

  if (request.passCountToFunction)
    Utils.invokeCommandString(request.command, [request.count])
  else
    Utils.invokeCommandString(request.command) for i in [0...request.count]

  refreshCompletionKeys(request)

#
# activatedElement is different from document.activeElement -- the latter seems to be reserved mostly for
# input elements. This mechanism allows us to decide whether to scroll a div or to scroll the whole document.
#
scrollActivatedElementBy = (direction, amount) ->
  # if this is called before domReady, just use the window scroll function
  if (!document.body)
    if (direction == "x")
      window.scrollBy(amount, 0)
    else
      window.scrollBy(0, amount)
    return

  # TODO refactor and put this together with the code in getVisibleClientRect
  isRendered = (element) ->
    computedStyle = window.getComputedStyle(element, null)
    return !(computedStyle.getPropertyValue("visibility") != "visible" ||
        computedStyle.getPropertyValue("display") == "none")

  if (!activatedElement || !isRendered(activatedElement))
    activatedElement = document.body

  scrollName = if (direction == "x") then "scrollLeft" else "scrollTop"

  # Chrome does not report scrollHeight accurately for nodes with pseudo-elements of height 0 (bug 110149).
  # Therefore we just try to increase scrollTop blindly -- if it fails we know we have reached the end of the
  # content.
  if (amount != 0)
    element = activatedElement
    loop
      oldScrollValue = element[scrollName]
      element[scrollName] += amount
      lastElement = element
      # we may have an orphaned element. if so, just scroll the body element.
      element = element.parentElement || document.body
      break unless (lastElement[scrollName] == oldScrollValue && lastElement != document.body)

  # if the activated element has been scrolled completely offscreen, subsequent changes in its scroll
  # position will not provide any more visual feedback to the user. therefore we deactivate it so that
  # subsequent scrolls only move the parent element.
  rect = activatedElement.getBoundingClientRect()
  if (rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth)
    activatedElement = lastElement

setScrollPosition = (scrollX, scrollY) ->
  if (scrollX > 0 || scrollY > 0)
    DomUtils.documentReady(-> window.scrollBy(scrollX, scrollY))

#
# Called from the backend in order to change frame focus.
#
window.focusThisFrame = (shouldHighlight) ->
  window.focus()
  if (document.body && shouldHighlight)
    borderWas = document.body.style.border
    document.body.style.border = '5px solid yellow'
    setTimeout((-> document.body.style.border = borderWas), 200)

extend window,
  scrollToBottom: -> window.scrollTo(window.pageXOffset, document.body.scrollHeight)
  scrollToTop: -> window.scrollTo(window.pageXOffset, 0)
  scrollToLeft: -> window.scrollTo(0, window.pageYOffset)
  scrollToRight: -> window.scrollTo(document.body.scrollWidth, window.pageYOffset)
  scrollUp: -> scrollActivatedElementBy("y", -1 * settings.get("scrollStepSize"))
  scrollDown: ->
    scrollActivatedElementBy("y", parseFloat(settings.get("scrollStepSize")))
  scrollPageUp: -> scrollActivatedElementBy("y", -1 * window.innerHeight / 2)
  scrollPageDown: -> scrollActivatedElementBy("y", window.innerHeight / 2)
  scrollFullPageUp: -> scrollActivatedElementBy("y", -window.innerHeight)
  scrollFullPageDown: -> scrollActivatedElementBy("y", window.innerHeight)
  scrollLeft: -> scrollActivatedElementBy("x", -1 * settings.get("scrollStepSize"))
  scrollRight: -> scrollActivatedElementBy("x", parseFloat(settings.get("scrollStepSize")))

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

  toggleViewSource: ->
    chrome.extension.sendRequest { handler: "getCurrentTabUrl" }, (url) ->
      if (url.substr(0, 12) == "view-source:")
        url = url.substr(12, url.length - 12)
      else
        url = "view-source:" + url
      chrome.extension.sendRequest({ handler: "openUrlInNewTab", url: url, selected: true })

  copyCurrentUrl: ->
    # TODO(ilya): When the following bug is fixed, revisit this approach of sending back to the background
    # page to copy.
    # http://code.google.com/p/chromium/issues/detail?id=55188
    chrome.extension.sendRequest { handler: "getCurrentTabUrl" }, (url) ->
      chrome.extension.sendRequest { handler: "copyToClipboard", data: url }

    HUD.showForDuration("Yanked URL", 1000)

  focusInput: (count) ->
    # Focus the first input element on the page, and create overlays to highlight all the input elements, with
    # the currently-focused element highlighted specially. Tabbing will shift focus to the next input element.
    # Pressing any other key will remove the overlays and the special tab behavior.
    resultSet = DomUtils.evaluateXPath(textInputXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE)
    visibleInputs =
      for i in [0...resultSet.snapshotLength] by 1
        element = resultSet.snapshotItem(i)
        rect = DomUtils.getVisibleClientRect(element)
        continue if rect == null
        { element: element, rect: rect }

    return if visibleInputs.length == 0

    selectedInputIndex = Math.min(count - 1, visibleInputs.length - 1)

    visibleInputs[selectedInputIndex].element.focus()

    return if visibleInputs.length == 1

    hints = for tuple in visibleInputs
      hint = document.createElement("div")
      hint.className = "vimiumReset internalVimiumInputHint vimiumInputHint"

      # minus 1 for the border
      hint.style.left = (tuple.rect.left - 1) + window.scrollX + "px"
      hint.style.top = (tuple.rect.top - 1) + window.scrollY  + "px"
      hint.style.width = tuple.rect.width + "px"
      hint.style.height = tuple.rect.height + "px"

      hint

    hints[selectedInputIndex].classList.add 'internalVimiumSelectedInputHint'

    hintContainingDiv = DomUtils.addElementList(hints,
      { id: "vimiumInputMarkerContainer", className: "vimiumReset" })

    handlerStack.push keydown: (event) ->
      if event.keyCode == KeyboardUtils.keyCodes.tab
        hints[selectedInputIndex].classList.remove 'internalVimiumSelectedInputHint'
        if event.shiftKey
          if --selectedInputIndex == -1
            selectedInputIndex = hints.length - 1
        else
          if ++selectedInputIndex == hints.length
            selectedInputIndex = 0
        hints[selectedInputIndex].classList.add 'internalVimiumSelectedInputHint'
        visibleInputs[selectedInputIndex].element.focus()
      else unless event.keyCode == KeyboardUtils.keyCodes.shiftKey
        DomUtils.removeElement hintContainingDiv
        @remove()

      false

# 
# Passkeys
#

isPasskey = ( keyChar ) ->
  passkeys && typeof(passkeys) == "string" and passkeys.indexOf(keyChar) >= 0

#
# Sends everything except i & ESC to the handler in background_page. i & ESC are special because they control
# insert mode which is local state to the page. The key will be are either a single ascii letter or a
# key-modifier pair, e.g. <c-a> for control a.
#
# Note that some keys will only register keydown events and not keystroke events, e.g. ESC.
#

onKeypress = (event) ->
  return unless handlerStack.bubbleEvent('keypress', event)

  keyChar = ""

  # Ignore modifier keys by themselves.
  if (event.keyCode > 31)
    keyChar = String.fromCharCode(event.charCode)

    # Enter insert mode when the user enables the native find interface.
    if (keyChar == "f" && KeyboardUtils.isPrimaryModifierKey(event))
      enterInsertModeWithoutShowingIndicator()
      return

    if (keyChar)
      if (findMode)
        handleKeyCharForFindMode(keyChar)
        DomUtils.suppressEvent(event)
      else if (!isInsertMode() && !findMode)
        if isPasskey keyChar
          console.log "onKeypress: passing #{keyChar}"
          return undefined
        if (currentCompletionKeys.indexOf(keyChar) != -1)
          DomUtils.suppressEvent(event)

        keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

onKeydown = (event) ->
  return unless handlerStack.bubbleEvent('keydown', event)

  keyChar = ""

  # handle special keys, and normal input keys with modifiers being pressed. don't handle shiftKey alone (to
  # avoid / being interpreted as ?
  if (((event.metaKey || event.ctrlKey || event.altKey) && event.keyCode > 31) ||
      event.keyIdentifier.slice(0, 2) != "U+")
    keyChar = KeyboardUtils.getKeyChar(event)
    # Again, ignore just modifiers. Maybe this should replace the keyCode>31 condition.
    if (keyChar != "")
      modifiers = []

      if (event.shiftKey)
        keyChar = keyChar.toUpperCase()
      if (event.metaKey)
        modifiers.push("m")
      if (event.ctrlKey)
        modifiers.push("c")
      if (event.altKey)
        modifiers.push("a")

      for i of modifiers
        keyChar = modifiers[i] + "-" + keyChar

      if (modifiers.length > 0 || keyChar.length > 1)
        keyChar = "<" + keyChar + ">"

  if (isInsertMode() && KeyboardUtils.isEscape(event))
    # Note that we can't programmatically blur out of Flash embeds from Javascript.
    if (!isEmbed(event.srcElement))
      # Remove focus so the user can't just get himself back into insert mode by typing in the same input
      # box.
      if (isEditable(event.srcElement))
        event.srcElement.blur()
      exitInsertMode()
      DomUtils.suppressEvent(event)

  else if (findMode)
    if (KeyboardUtils.isEscape(event))
      handleEscapeForFindMode()
      DomUtils.suppressEvent(event)

    else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey)
      handleDeleteForFindMode()
      DomUtils.suppressEvent(event)

    else if (event.keyCode == keyCodes.enter)
      handleEnterForFindMode()
      DomUtils.suppressEvent(event)

    else if (!modifiers)
      event.stopPropagation()

  else if (isShowingHelpDialog && KeyboardUtils.isEscape(event))
    hideHelpDialog()

  else if (!isInsertMode() && !findMode)
    if (keyChar)
      if (currentCompletionKeys.indexOf(keyChar) != -1)
        DomUtils.suppressEvent(event)

      keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

    else if (KeyboardUtils.isEscape(event))
      keyPort.postMessage({ keyChar:"<ESC>", frameId:frameId })
  
    # passkeys:
    #   only if no meta/control/alt key
    #   only if !isInsertMode
    #   only if !findMode
    #   only if not "<ESC>
    else
      if isPasskey KeyboardUtils.getKeyChar(event)
        console.log "onKeydown: passing #{KeyboardUtils.getKeyChar(event)}"
        return undefined

  # Added to prevent propagating this event to other listeners if it's one that'll trigger a Vimium command.
  # The goal is to avoid the scenario where Google Instant Search uses every keydown event to dump us
  # back into the search box. As a side effect, this should also prevent overriding by other sites.
  #
  # Subject to internationalization issues since we're using keyIdentifier instead of charCode (in keypress).
  #
  # TOOD(ilya): Revisit @ Not sure it's the absolute best approach.
  if (keyChar == "" && !isInsertMode() &&
     (currentCompletionKeys.indexOf(KeyboardUtils.getKeyChar(event)) != -1 ||
      isValidFirstKey(KeyboardUtils.getKeyChar(event))))
    event.stopPropagation()

onKeyup = (event) -> return unless handlerStack.bubbleEvent('keyup', event)

checkIfEnabledForUrl = ->
  url = window.location.toString()

  chrome.extension.sendRequest { handler: "isEnabledForUrl", url: url }, (response) ->
    isEnabledForUrl = response.isEnabledForUrl
    if (isEnabledForUrl)
      initializeWhenEnabled(response)
    else if (HUD.isReady())
      # Quickly hide any HUD we might already be showing, e.g. if we entered insert mode on page load.
      HUD.hide()

refreshCompletionKeys = (response) ->
  if (response)
    currentCompletionKeys = response.completionKeys

    if (response.validFirstKeys)
      validFirstKeys = response.validFirstKeys
  else
    chrome.extension.sendRequest({ handler: "getCompletionKeys" }, refreshCompletionKeys)

isValidFirstKey = (keyChar) ->
  validFirstKeys[keyChar] || /[1-9]/.test(keyChar)

onFocusCapturePhase = (event) ->
  if (isFocusable(event.target) && !findMode)
    enterInsertModeWithoutShowingIndicator(event.target)

onBlurCapturePhase = (event) ->
  if (isFocusable(event.target))
    exitInsertMode(event.target)

#
# Returns true if the element is focusable. This includes embeds like Flash, which steal the keybaord focus.
#
isFocusable = (element) -> isEditable(element) || isEmbed(element)

#
# Embedded elements like Flash and quicktime players can obtain focus but cannot be programmatically
# unfocused.
#
isEmbed = (element) -> ["embed", "object"].indexOf(element.nodeName.toLowerCase()) > 0

#
# Input or text elements are considered focusable and able to receieve their own keyboard events,
# and will enter enter mode if focused. Also note that the "contentEditable" attribute can be set on
# any element which makes it a rich text editor, like the notes on jjot.com.
#
isEditable = (target) ->
  return true if target.isContentEditable
  nodeName = target.nodeName.toLowerCase()
  # use a blacklist instead of a whitelist because new form controls are still being implemented for html5
  noFocus = ["radio", "checkbox"]
  if (nodeName == "input" && noFocus.indexOf(target.type) == -1)
    return true
  focusableElements = ["textarea", "select"]
  focusableElements.indexOf(nodeName) >= 0

#
# Enters insert mode and show an "Insert mode" message. Showing the UI is only useful when entering insert
# mode manually by pressing "i". In most cases we do not show any UI (enterInsertModeWithoutShowingIndicator)
#
window.enterInsertMode = (target) ->
  enterInsertModeWithoutShowingIndicator(target)
  HUD.show("Insert mode")

#
# We cannot count on 'focus' and 'blur' events to happen sequentially. For example, if blurring element A
# causes element B to come into focus, we may get "B focus" before "A blur". Thus we only leave insert mode
# when the last editable element that came into focus -- which insertModeLock points to -- has been blurred.
# If insert mode is entered manually (via pressing 'i'), then we set insertModeLock to 'undefined', and only
# leave insert mode when the user presses <ESC>.
#
enterInsertModeWithoutShowingIndicator = (target) -> insertModeLock = target

exitInsertMode = (target) ->
  if (target == undefined || insertModeLock == target)
    insertModeLock = null
    HUD.hide()

isInsertMode = -> insertModeLock != null

# should be called whenever rawQuery is modified.
updateFindModeQuery = ->
  # the query can be treated differently (e.g. as a plain string versus regex depending on the presence of
  # escape sequences. '\' is the escape character and needs to be escaped itself to be used as a normal
  # character. here we grep for the relevant escape sequences.
  findModeQuery.isRegex = settings.get 'regexFindMode'
  hasNoIgnoreCaseFlag = false
  findModeQuery.parsedQuery = findModeQuery.rawQuery.replace /\\./g, (match) ->
    switch (match)
      when "\\r"
        findModeQuery.isRegex = true
        return ""
      when "\\R"
        findModeQuery.isRegex = false
        return ""
      when "\\I"
        hasNoIgnoreCaseFlag = true
        return ""
      when "\\\\"
        return "\\"
      else
        return match

  # default to 'smartcase' mode, unless noIgnoreCase is explicitly specified
  findModeQuery.ignoreCase = !hasNoIgnoreCaseFlag && !/[A-Z]/.test(findModeQuery.parsedQuery)

  # if we are dealing with a regex, grep for all matches in the text, and then call window.find() on them
  # sequentially so the browser handles the scrolling / text selection.
  if findModeQuery.isRegex
    try
      pattern = new RegExp(findModeQuery.parsedQuery, "g" + (if findModeQuery.ignoreCase then "i" else ""))
    catch error
      # if we catch a SyntaxError, assume the user is not done typing yet and return quietly
      return
    # innerText will not return the text of hidden elements, and strip out tags while preserving newlines
    text = document.body.innerText
    findModeQuery.regexMatches = text.match(pattern)
    findModeQuery.activeRegexIndex = 0

handleKeyCharForFindMode = (keyChar) ->
  findModeQuery.rawQuery += keyChar
  updateFindModeQuery()
  performFindInPlace()
  showFindModeHUDForQuery()

handleEscapeForFindMode = ->
  exitFindMode()
  document.body.classList.remove("vimiumFindMode")
  # removing the class does not re-color existing selections. we recreate the current selection so it reverts
  # back to the default color.
  selection = window.getSelection()
  unless selection.isCollapsed
    range = window.getSelection().getRangeAt(0)
    window.getSelection().removeAllRanges()
    window.getSelection().addRange(range)
  focusFoundLink() || selectFoundInputElement()

handleDeleteForFindMode = ->
  if (findModeQuery.rawQuery.length == 0)
    exitFindMode()
    performFindInPlace()
  else
    findModeQuery.rawQuery = findModeQuery.rawQuery.substring(0, findModeQuery.rawQuery.length - 1)
    updateFindModeQuery()
    performFindInPlace()
    showFindModeHUDForQuery()

# <esc> sends us into insert mode if possible, but <cr> does not.
# <esc> corresponds approximately to 'nevermind, I have found it already' while <cr> means 'I want to save
# this query and do more searches with it'
handleEnterForFindMode = ->
  exitFindMode()
  focusFoundLink()
  document.body.classList.add("vimiumFindMode")
  settings.set("findModeRawQuery", findModeQuery.rawQuery)

performFindInPlace = ->
  cachedScrollX = window.scrollX
  cachedScrollY = window.scrollY

  query = if findModeQuery.isRegex then getNextQueryFromRegexMatches(0) else findModeQuery.parsedQuery

  # Search backwards first to "free up" the current word as eligible for the real forward search. This allows
  # us to search in place without jumping around between matches as the query grows.
  executeFind(query, { backwards: true, caseSensitive: !findModeQuery.ignoreCase })

  # We need to restore the scroll position because we might've lost the right position by searching
  # backwards.
  window.scrollTo(cachedScrollX, cachedScrollY)

  findModeQueryHasResults = executeFind(query, { caseSensitive: !findModeQuery.ignoreCase })

# :options is an optional dict. valid parameters are 'caseSensitive' and 'backwards'.
executeFind = (query, options) ->
  options = options || {}

  # rather hacky, but this is our way of signalling to the insertMode listener not to react to the focus
  # changes that find() induces.
  oldFindMode = findMode
  findMode = true

  document.body.classList.add("vimiumFindMode")

  # prevent find from matching its own search query in the HUD
  HUD.hide(true)
  # ignore the selectionchange event generated by find()
  document.removeEventListener("selectionchange",restoreDefaultSelectionHighlight, true)
  result = window.find(query, options.caseSensitive, options.backwards, true, false, true, false)
  setTimeout(
    -> document.addEventListener("selectionchange", restoreDefaultSelectionHighlight, true)
    0)

  findMode = oldFindMode
  # we need to save the anchor node here because <esc> seems to nullify it, regardless of whether we do
  # preventDefault()
  findModeAnchorNode = document.getSelection().anchorNode
  result

restoreDefaultSelectionHighlight = -> document.body.classList.remove("vimiumFindMode")

focusFoundLink = ->
  if (findModeQueryHasResults)
    link = getLinkFromSelection()
    link.focus() if link

isDOMDescendant = (parent, child) ->
  node = child
  while (node != null)
    return true if (node == parent)
    node = node.parentNode
  false

selectFoundInputElement = ->
  # if the found text is in an input element, getSelection().anchorNode will be null, so we use activeElement
  # instead. however, since the last focused element might not be the one currently pointed to by find (e.g.
  # the current one might be disabled and therefore unable to receive focus), we use the approximate
  # heuristic of checking that the last anchor node is an ancestor of our element.
  if (findModeQueryHasResults && document.activeElement &&
      DomUtils.isSelectable(document.activeElement) &&
      isDOMDescendant(findModeAnchorNode, document.activeElement))
    DomUtils.simulateSelect(document.activeElement)
    # the element has already received focus via find(), so invoke insert mode manually
    enterInsertModeWithoutShowingIndicator(document.activeElement)

getNextQueryFromRegexMatches = (stepSize) ->
  # find()ing an empty query always returns false
  return "" unless findModeQuery.regexMatches

  totalMatches = findModeQuery.regexMatches.length
  findModeQuery.activeRegexIndex += stepSize + totalMatches
  findModeQuery.activeRegexIndex %= totalMatches

  findModeQuery.regexMatches[findModeQuery.activeRegexIndex]

findAndFocus = (backwards) ->
  # check if the query has been changed by a script in another frame
  mostRecentQuery = settings.get("findModeRawQuery") || ""
  if (mostRecentQuery != findModeQuery.rawQuery)
    findModeQuery.rawQuery = mostRecentQuery
    updateFindModeQuery()

  query =
    if findModeQuery.isRegex
      getNextQueryFromRegexMatches(if backwards then -1 else 1)
    else
      findModeQuery.parsedQuery

  findModeQueryHasResults =
    executeFind(query, { backwards: backwards, caseSensitive: !findModeQuery.ignoreCase })

  if (!findModeQueryHasResults)
    HUD.showForDuration("No matches for '" + findModeQuery.rawQuery + "'", 1000)
    return

  # if we have found an input element via 'n', pressing <esc> immediately afterwards sends us into insert
  # mode
  elementCanTakeInput = document.activeElement &&
    DomUtils.isSelectable(document.activeElement) &&
    isDOMDescendant(findModeAnchorNode, document.activeElement)
  if (elementCanTakeInput)
    handlerStack.push({
      keydown: (event) ->
        @remove()
        if (KeyboardUtils.isEscape(event))
          DomUtils.simulateSelect(document.activeElement)
          enterInsertModeWithoutShowingIndicator(document.activeElement)
          return false # we have "consumed" this event, so do not propagate
        return true
    })

  focusFoundLink()

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
      if (element.hasAttribute("rel") && element.rel == value)
        followLink(element)
        return true

window.goPrevious = ->
  previousPatterns = settings.get("previousPatterns") || ""
  previousStrings = previousPatterns.split(",").filter((s) -> s.length)
  findAndFollowRel("prev") || findAndFollowLink(previousStrings)

window.goNext = ->
  nextPatterns = settings.get("nextPatterns") || ""
  nextStrings = nextPatterns.split(",").filter((s) -> s.length)
  findAndFollowRel("next") || findAndFollowLink(nextStrings)

showFindModeHUDForQuery = ->
  if (findModeQueryHasResults || findModeQuery.parsedQuery.length == 0)
    HUD.show("/" + findModeQuery.rawQuery)
  else
    HUD.show("/" + findModeQuery.rawQuery + " (No Matches)")

window.enterFindMode = ->
  findModeQuery = { rawQuery: "" }
  findMode = true
  HUD.show("/")

exitFindMode = ->
  findMode = false
  HUD.hide()

window.showHelpDialog = (html, fid) ->
  return if (isShowingHelpDialog || !document.body || fid != frameId)
  isShowingHelpDialog = true
  container = document.createElement("div")
  container.id = "vimiumHelpDialogContainer"
  container.className = "vimiumReset"

  document.body.appendChild(container)

  container.innerHTML = html
  container.getElementsByClassName("closeButton")[0].addEventListener("click", hideHelpDialog, false)
  
  VimiumHelpDialog =
    # This setting is pulled out of local storage. It's false by default.
    getShowAdvancedCommands: -> settings.get("helpDialog_showAdvancedCommands")

    init: () ->
      this.dialogElement = document.getElementById("vimiumHelpDialog")
      this.dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].addEventListener("click",
        VimiumHelpDialog.toggleAdvancedCommands, false)
      this.dialogElement.style.maxHeight = window.innerHeight - 80
      this.showAdvancedCommands(this.getShowAdvancedCommands())

    #
    # Advanced commands are hidden by default so they don't overwhelm new and casual users.
    #
    toggleAdvancedCommands: (event) ->
      event.preventDefault()
      showAdvanced = VimiumHelpDialog.getShowAdvancedCommands()
      VimiumHelpDialog.showAdvancedCommands(!showAdvanced)
      settings.set("helpDialog_showAdvancedCommands", !showAdvanced)

    showAdvancedCommands: (visible) ->
      VimiumHelpDialog.dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].innerHTML =
        if visible then "Hide advanced commands" else "Show advanced commands"
      advancedEls = VimiumHelpDialog.dialogElement.getElementsByClassName("advanced")
      for el in advancedEls
        el.style.display = if visible then "table-row" else "none"

  VimiumHelpDialog.init()

  container.getElementsByClassName("optionsPage")[0].addEventListener("click",
    -> chrome.extension.sendRequest({ handler: "openOptionsPageInNewTab" })
    false)


hideHelpDialog = (clickEvent) ->
  isShowingHelpDialog = false
  helpDialog = document.getElementById("vimiumHelpDialogContainer")
  if (helpDialog)
    helpDialog.parentNode.removeChild(helpDialog)
  if (clickEvent)
    clickEvent.preventDefault()

toggleHelpDialog = (html, fid) ->
  if (isShowingHelpDialog)
    hideHelpDialog()
  else
    showHelpDialog(html, fid)

#
# A heads-up-display (HUD) for showing Vimium page operations.
# Note: you cannot interact with the HUD until document.body is available.
#
HUD =
  _tweenId: -1
  _displayElement: null
  _upgradeNotificationElement: null

  # This HUD is styled to precisely mimick the chrome HUD on Mac. Use the "has_popup_and_link_hud.html"
  # test harness to tweak these styles to match Chrome's. One limitation of our HUD display is that
  # it doesn't sit on top of horizontal scrollbars like Chrome's HUD does.

  showForDuration: (text, duration) ->
    HUD.show(text)
    HUD._showForDurationTimerId = setTimeout((-> HUD.hide()), duration)

  show: (text) ->
    return unless HUD.enabled()
    clearTimeout(HUD._showForDurationTimerId)
    HUD.displayElement().innerHTML = text
    clearInterval(HUD._tweenId)
    HUD._tweenId = Tween.fade(HUD.displayElement(), 1.0, 150)
    HUD.displayElement().style.display = ""

  showUpgradeNotification: (version) ->
    HUD.upgradeNotificationElement().innerHTML = "Vimium has been updated to
      <a class='vimiumReset'
      href='https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb'>
      #{version}</a>.<a class='vimiumReset close-button' href='#'>x</a>"
    links = HUD.upgradeNotificationElement().getElementsByTagName("a")
    links[0].addEventListener("click", HUD.onUpdateLinkClicked, false)
    links[1].addEventListener "click", (event) ->
      event.preventDefault()
      HUD.onUpdateLinkClicked()
    Tween.fade(HUD.upgradeNotificationElement(), 1.0, 150)

  onUpdateLinkClicked: (event) ->
    HUD.hideUpgradeNotification()
    chrome.extension.sendRequest({ handler: "upgradeNotificationClosed" })

  hideUpgradeNotification: (clickEvent) ->
    Tween.fade(HUD.upgradeNotificationElement(), 0, 150,
      -> HUD.upgradeNotificationElement().style.display = "none")

  #
  # Retrieves the HUD HTML element.
  #
  displayElement: ->
    if (!HUD._displayElement)
      HUD._displayElement = HUD.createHudElement()
      # Keep this far enough to the right so that it doesn't collide with the "popups blocked" chrome HUD.
      HUD._displayElement.style.right = "150px"
    HUD._displayElement

  upgradeNotificationElement: ->
    if (!HUD._upgradeNotificationElement)
      HUD._upgradeNotificationElement = HUD.createHudElement()
      # Position this just to the left of our normal HUD.
      HUD._upgradeNotificationElement.style.right = "315px"
    HUD._upgradeNotificationElement

  createHudElement: ->
    element = document.createElement("div")
    element.className = "vimiumReset vimiumHUD"
    document.body.appendChild(element)
    element

  hide: (immediate) ->
    clearInterval(HUD._tweenId)
    if (immediate)
      HUD.displayElement().style.display = "none"
    else
      HUD._tweenId = Tween.fade(HUD.displayElement(), 0, 150,
        -> HUD.displayElement().style.display = "none")

  isReady: -> document.body != null

  # A preference which can be toggled in the Options page. */
  enabled: -> !settings.get("hideHud")

Tween =
  #
  # Fades an element's alpha. Returns a timer ID which can be used to stop the tween via clearInterval.
  #
  fade: (element, toAlpha, duration, onComplete) ->
    state = {}
    state.duration = duration
    state.startTime = (new Date()).getTime()
    state.from = parseInt(element.style.opacity) || 0
    state.to = toAlpha
    state.onUpdate = (value) ->
      element.style.opacity = value
      if (value == state.to && onComplete)
        onComplete()
    state.timerId = setInterval((-> Tween.performTweenStep(state)), 50)
    state.timerId

  performTweenStep: (state) ->
    elapsed = (new Date()).getTime() - state.startTime
    if (elapsed >= state.duration)
      clearInterval(state.timerId)
      state.onUpdate(state.to)
    else
      value = (elapsed / state.duration)  * (state.to - state.from) + state.from
      state.onUpdate(value)

initializePreDomReady()
window.addEventListener("DOMContentLoaded", initializeOnDomReady)

window.onbeforeunload = ->
  chrome.extension.sendRequest(
    handler: "updateScrollPosition"
    scrollX: window.scrollX
    scrollY: window.scrollY)

root = exports ? window
root.settings = settings
root.HUD = HUD
root.handlerStack = handlerStack
root.frameId = frameId

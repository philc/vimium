#
# This implements link hinting. Typing "F" will enter link-hinting mode, where all clickable items on the
# page have a hint marker displayed containing a sequence of letters. Typing those letters will select a link.
#
# In our 'default' mode, the characters we use to show link hints are a user-configurable option. By default
# they're the home row.  The CSS which is used on the link hints is also a configurable option.
#
# In 'filter' mode, our link hints are numbers, and the user can narrow down the range of possibilities by
# typing the text of the link itself.
#
OPEN_IN_CURRENT_TAB = {}
OPEN_IN_NEW_BG_TAB = {}
OPEN_IN_NEW_FG_TAB = {}
OPEN_WITH_QUEUE = {}
COPY_LINK_URL = {}
OPEN_INCOGNITO = {}

LinkHints =
  hintMarkerContainingDiv: null
  # one of the enums listed at the top of this file
  mode: undefined
  # function that does the appropriate action on the selected link
  linkActivator: undefined
  # While in delayMode, all keypresses have no effect.
  delayMode: false
  # Handle the link hinting marker generation and matching. Must be initialized after settings have been
  # loaded, so that we can retrieve the option setting.
  getMarkerMatcher: ->
    if settings.get("filterLinkHints") then filterHints else alphabetHints
  # lock to ensure only one instance runs at a time
  isActive: false

  #
  # To be called after linkHints has been generated from linkHintsBase.
  #
  init: ->

  #
  # Generate an XPath describing what a clickable element is.
  # The final expression will be something like "//button | //xhtml:button | ..."
  # We use translate() instead of lower-case() because Chrome only supports XPath 1.0.
  #
  clickableElementsXPath: DomUtils.makeXPath(
    ["a", "area[@href]", "textarea", "button", "select",
     "input[not(@type='hidden' or @disabled or @readonly)]",
     "*[@onclick or @tabindex or @role='link' or @role='button' or contains(@class, 'button') or " +
     "@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"])

  # We need this as a top-level function because our command system doesn't yet support arguments.
  activateModeToOpenInNewTab: -> @activateMode(OPEN_IN_NEW_BG_TAB)
  activateModeToOpenInNewForegroundTab: -> @activateMode(OPEN_IN_NEW_FG_TAB)
  activateModeToCopyLinkUrl: -> @activateMode(COPY_LINK_URL)
  activateModeWithQueue: -> @activateMode(OPEN_WITH_QUEUE)
  activateModeToOpenIncognito: -> @activateMode(OPEN_INCOGNITO)

  activateMode: (mode = OPEN_IN_CURRENT_TAB) ->
    # we need documentElement to be ready in order to append links
    return unless document.documentElement

    if @isActive
      return
    @isActive = true

    @setOpenLinkMode(mode)
    hintMarkers = (@createMarkerFor(el) for el in @getVisibleClickableElements())
    @getMarkerMatcher().fillInMarkers(hintMarkers)

    # Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    # because some clickable elements cannot contain children, e.g. submit buttons. This has the caveat
    # that if you scroll the page and the link has position=fixed, the marker will not stay fixed.
    @hintMarkerContainingDiv = DomUtils.addElementList(hintMarkers,
      { id: "vimiumHintMarkerContainer", className: "vimiumReset" })

    # handlerStack is declared by vimiumFrontend.js
    @handlerId = handlerStack.push({
      keydown: @onKeyDownInMode.bind(this, hintMarkers),
      # trap all key events
      keypress: -> false
      keyup: -> false
    })

  setOpenLinkMode: (@mode) ->
    if @mode is OPEN_IN_NEW_BG_TAB or @mode is OPEN_IN_NEW_FG_TAB or @mode is OPEN_WITH_QUEUE
      if @mode is OPEN_IN_NEW_BG_TAB
        HUD.show("Open link in new tab")
      else if @mode is OPEN_IN_NEW_FG_TAB
        HUD.show("Open link in new tab and switch to it")
      else
        HUD.show("Open multiple links in a new tab")
      @linkActivator = (link) ->
        # When "clicking" on a link, dispatch the event with the appropriate meta key (CMD on Mac, CTRL on
        # windows) to open it in a new tab if necessary.
        DomUtils.simulateClick(link, {
          shiftKey: @mode is OPEN_IN_NEW_FG_TAB,
          metaKey: KeyboardUtils.platform == "Mac",
          ctrlKey: KeyboardUtils.platform != "Mac" })
    else if @mode is COPY_LINK_URL
      HUD.show("Copy link URL to Clipboard")
      @linkActivator = (link) ->
        chrome.runtime.sendMessage({handler: "copyToClipboard", data: link.href})
    else if @mode is OPEN_INCOGNITO
      HUD.show("Open link in incognito window")

      @linkActivator = (link) ->
        chrome.runtime.sendMessage(
          handler: 'openUrlInIncognito'
          url: link.href)
    else # OPEN_IN_CURRENT_TAB
      HUD.show("Open link in current tab")
      @linkActivator = (link) -> DomUtils.simulateClick.bind(DomUtils, link)()

  #
  # Creates a link marker for the given link.
  #
  createMarkerFor: (link) ->
    marker = document.createElement("div")
    marker.className = "vimiumReset internalVimiumHintMarker vimiumHintMarker"
    marker.clickableItem = link.element

    clientRect = link.rect
    marker.style.left = clientRect.left + window.scrollX + "px"
    marker.style.top = clientRect.top  + window.scrollY  + "px"

    marker.rect = link.rect

    marker

  #
  # Returns all clickable elements that are not hidden and are in the current viewport.
  # We prune invisible elements partly for performance reasons, but moreso it's to decrease the number
  # of digits needed to enumerate all of the links on screen.
  #
  getVisibleClickableElements: ->
    resultSet = DomUtils.evaluateXPath(@clickableElementsXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE)

    visibleElements = []

    # Find all visible clickable elements.
    for i in [0...resultSet.snapshotLength] by 1
      element = resultSet.snapshotItem(i)
      clientRect = DomUtils.getVisibleClientRect(element, clientRect)
      if (clientRect != null)
        visibleElements.push({element: element, rect: clientRect})

      if (element.localName == "area")
        map = element.parentElement
        continue unless map
        img = document.querySelector("img[usemap='#" + map.getAttribute("name") + "']")
        continue unless img
        imgClientRects = img.getClientRects()
        continue if (imgClientRects.length == 0)
        c = element.coords.split(/,/)
        coords = [parseInt(c[0], 10), parseInt(c[1], 10), parseInt(c[2], 10), parseInt(c[3], 10)]
        rect = {
          top: imgClientRects[0].top + coords[1],
          left: imgClientRects[0].left + coords[0],
          right: imgClientRects[0].left + coords[2],
          bottom: imgClientRects[0].top + coords[3],
          width: coords[2] - coords[0],
          height: coords[3] - coords[1]
        }

        visibleElements.push({element: element, rect: rect})

    visibleElements

  #
  # Handles shift and esc keys. The other keys are passed to getMarkerMatcher().matchHintsByKey.
  #
  onKeyDownInMode: (hintMarkers, event) ->
    return if @delayMode

    if ((event.keyCode == keyCodes.shiftKey or event.keyCode == keyCodes.ctrlKey) and
        (@mode == OPEN_IN_CURRENT_TAB or
         @mode == OPEN_IN_NEW_BG_TAB or
         @mode == OPEN_IN_NEW_FG_TAB))
      # Toggle whether to open link in a new or current tab.
      prev_mode = @mode

      if event.keyCode == keyCodes.shiftKey
        @setOpenLinkMode(if @mode is OPEN_IN_CURRENT_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_CURRENT_TAB)

      else # event.keyCode == keyCodes.ctrlKey
        @setOpenLinkMode(if @mode is OPEN_IN_NEW_FG_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_NEW_FG_TAB)

    # TODO(philc): Ignore keys that have modifiers.
    if (KeyboardUtils.isEscape(event))
      @deactivateMode()
    else
      keyResult = @getMarkerMatcher().matchHintsByKey(hintMarkers, event)
      linksMatched = keyResult.linksMatched
      delay = keyResult.delay ? 0
      if (linksMatched.length == 0)
        @deactivateMode()
      else if (linksMatched.length == 1)
        @activateLink(linksMatched[0], delay)
      else
        for marker in hintMarkers
          @hideMarker(marker)
        for matched in linksMatched
          @showMarker(matched, @getMarkerMatcher().hintKeystrokeQueue.length)
    false # We've handled this key, so prevent propagation.

  #
  # When only one link hint remains, this function activates it in the appropriate way.
  #
  activateLink: (matchedLink, delay) ->
    @delayMode = true
    clickEl = matchedLink.clickableItem
    if (DomUtils.isSelectable(clickEl))
      DomUtils.simulateSelect(clickEl)
      @deactivateMode(delay, -> LinkHints.delayMode = false)
    else
      # TODO figure out which other input elements should not receive focus
      if (clickEl.nodeName.toLowerCase() == "input" && clickEl.type != "button")
        clickEl.focus()
      DomUtils.flashRect(matchedLink.rect)
      @linkActivator(clickEl)
      if @mode is OPEN_WITH_QUEUE
        @deactivateMode delay, ->
          LinkHints.delayMode = false
          LinkHints.activateModeWithQueue()
      else
        @deactivateMode(delay, -> LinkHints.delayMode = false)

  #
  # Shows the marker, highlighting matchingCharCount characters.
  #
  showMarker: (linkMarker, matchingCharCount) ->
    linkMarker.style.display = ""
    # TODO(philc):
    for j in [0...linkMarker.childNodes.length]
      if (j < matchingCharCount)
        linkMarker.childNodes[j].classList.add("matchingCharacter")
      else
        linkMarker.childNodes[j].classList.remove("matchingCharacter")

  hideMarker: (linkMarker) -> linkMarker.style.display = "none"

  #
  # If called without arguments, it executes immediately.  Othewise, it
  # executes after 'delay' and invokes 'callback' when it is finished.
  #
  deactivateMode: (delay, callback) ->
    deactivate = =>
      if (LinkHints.getMarkerMatcher().deactivate)
        LinkHints.getMarkerMatcher().deactivate()
      if (LinkHints.hintMarkerContainingDiv)
        DomUtils.removeElement LinkHints.hintMarkerContainingDiv
      LinkHints.hintMarkerContainingDiv = null
      handlerStack.remove @handlerId
      HUD.hide()
      @isActive = false

    # we invoke the deactivate() function directly instead of using setTimeout(callback, 0) so that
    # deactivateMode can be tested synchronously
    if (!delay)
      deactivate()
      callback() if (callback)
    else
      setTimeout(->
        deactivate()
        callback() if callback
      delay)

alphabetHints =
  hintKeystrokeQueue: []
  logXOfBase: (x, base) -> Math.log(x) / Math.log(base)

  fillInMarkers: (hintMarkers) ->
    hintStrings = @hintStrings(hintMarkers.length)
    for marker, idx in hintMarkers
      marker.hintString = hintStrings[idx]
      marker.innerHTML = spanWrap(marker.hintString.toUpperCase())

    hintMarkers

  #
  # Returns a list of hint strings which will uniquely identify the given number of links. The hint strings
  # may be of different lengths.
  #
  hintStrings: (linkCount) ->
    linkHintCharacters = settings.get("linkHintCharacters")
    # Determine how many digits the link hints will require in the worst case. Usually we do not need
    # all of these digits for every link single hint, so we can show shorter hints for a few of the links.
    digitsNeeded = Math.ceil(@logXOfBase(linkCount, linkHintCharacters.length))
    # Short hints are the number of hints we can possibly show which are (digitsNeeded - 1) digits in length.
    shortHintCount = Math.floor(
      (Math.pow(linkHintCharacters.length, digitsNeeded) - linkCount) /
      linkHintCharacters.length)
    longHintCount = linkCount - shortHintCount

    hintStrings = []

    if (digitsNeeded > 1)
      for i in [0...shortHintCount]
        hintStrings.push(numberToHintString(i, linkHintCharacters, digitsNeeded - 1))

    start = shortHintCount * linkHintCharacters.length
    for i in [start...(start + longHintCount)]
      hintStrings.push(numberToHintString(i, linkHintCharacters, digitsNeeded))

    @shuffleHints(hintStrings, linkHintCharacters.length)

  #
  # This shuffles the given set of hints so that they're scattered -- hints starting with the same character
  # will be spread evenly throughout the array.
  #
  shuffleHints: (hints, characterSetLength) ->
    buckets = ([] for i in [0...characterSetLength] by 1)
    for hint, i in hints
      buckets[i % buckets.length].push(hint)
    result = []
    for bucket in buckets
      result = result.concat(bucket)
    result

  matchHintsByKey: (hintMarkers, event) ->
    # If a shifted-character is typed, treat it as lowerase for the purposes of matching hints.
    keyChar = KeyboardUtils.getKeyChar(event).toLowerCase()

    if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey)
      if (!@hintKeystrokeQueue.pop())
        return { linksMatched: [] }
    else if keyChar
      @hintKeystrokeQueue.push(keyChar)

    matchString = @hintKeystrokeQueue.join("")
    linksMatched = hintMarkers.filter((linkMarker) -> linkMarker.hintString.indexOf(matchString) == 0)
    { linksMatched: linksMatched }

  deactivate: -> @hintKeystrokeQueue = []

filterHints =
  hintKeystrokeQueue: []
  linkTextKeystrokeQueue: []
  labelMap: {}

  #
  # Generate a map of input element => label
  #
  generateLabelMap: ->
    labels = document.querySelectorAll("label")
    for label in labels
      forElement = label.getAttribute("for")
      if (forElement)
        labelText = label.textContent.trim()
        # remove trailing : commonly found in labels
        if (labelText[labelText.length-1] == ":")
          labelText = labelText.substr(0, labelText.length-1)
        @labelMap[forElement] = labelText

  generateHintString: (linkHintNumber) ->
    (numberToHintString linkHintNumber + 1, settings.get "linkHintNumbers").toUpperCase()

  generateLinkText: (element) ->
    linkText = ""
    showLinkText = false
    # toLowerCase is necessary as html documents return "IMG" and xhtml documents return "img"
    nodeName = element.nodeName.toLowerCase()

    if (nodeName == "input")
      if (@labelMap[element.id])
        linkText = @labelMap[element.id]
        showLinkText = true
      else if (element.type != "password")
        linkText = element.value
        if not linkText and 'placeholder' of element
          linkText = element.placeholder
      # check if there is an image embedded in the <a> tag
    else if (nodeName == "a" && !element.textContent.trim() &&
        element.firstElementChild &&
        element.firstElementChild.nodeName.toLowerCase() == "img")
      linkText = element.firstElementChild.alt || element.firstElementChild.title
      showLinkText = true if (linkText)
    else
      linkText = element.textContent || element.innerHTML

    { text: linkText, show: showLinkText }

  renderMarker: (marker) ->
    marker.innerHTML = spanWrap(marker.hintString +
        (if marker.showLinkText then ": " + marker.linkText else ""))

  fillInMarkers: (hintMarkers) ->
    @generateLabelMap()
    for marker, idx in hintMarkers
      marker.hintString = @generateHintString(idx)
      linkTextObject = @generateLinkText(marker.clickableItem)
      marker.linkText = linkTextObject.text
      marker.showLinkText = linkTextObject.show
      @renderMarker(marker)

    hintMarkers

  matchHintsByKey: (hintMarkers, event) ->
    keyChar = KeyboardUtils.getKeyChar(event)
    delay = 0
    userIsTypingLinkText = false

    if (event.keyCode == keyCodes.enter)
      # activate the lowest-numbered link hint that is visible
      for marker in hintMarkers
        if (marker.style.display != "none")
          return { linksMatched: [ marker ] }
    else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey)
      # backspace clears hint key queue first, then acts on link text key queue.
      # if both queues are empty. exit hinting mode
      if (!@hintKeystrokeQueue.pop() && !@linkTextKeystrokeQueue.pop())
        return { linksMatched: [] }
    else if (keyChar)
      if (settings.get("linkHintNumbers").indexOf(keyChar) >= 0)
        @hintKeystrokeQueue.push(keyChar)
      else
        # since we might renumber the hints, the current hintKeyStrokeQueue
        # should be rendered invalid (i.e. reset).
        @hintKeystrokeQueue = []
        @linkTextKeystrokeQueue.push(keyChar)
        userIsTypingLinkText = true

    # at this point, linkTextKeystrokeQueue and hintKeystrokeQueue have been updated to reflect the latest
    # input. use them to filter the link hints accordingly.
    linksMatched = @filterLinkHints(hintMarkers)
    matchString = @hintKeystrokeQueue.join("")
    linksMatched = linksMatched.filter((linkMarker) ->
      !linkMarker.filtered && linkMarker.hintString.indexOf(matchString) == 0)

    if (linksMatched.length == 1 && userIsTypingLinkText)
      # In filter mode, people tend to type out words past the point
      # needed for a unique match. Hence we should avoid passing
      # control back to command mode immediately after a match is found.
      delay = 200

    { linksMatched: linksMatched, delay: delay }

  #
  # Marks the links that do not match the linkText search string with the 'filtered' DOM property. Renumbers
  # the remainder if necessary.
  #
  filterLinkHints: (hintMarkers) ->
    linksMatched = []
    linkSearchString = @linkTextKeystrokeQueue.join("")

    for linkMarker in hintMarkers
      matchedLink = linkMarker.linkText.toLowerCase().indexOf(linkSearchString.toLowerCase()) >= 0

      if (!matchedLink)
        linkMarker.filtered = true
      else
        linkMarker.filtered = false
        oldHintString = linkMarker.hintString
        linkMarker.hintString = @generateHintString(linksMatched.length)
        @renderMarker(linkMarker) if (linkMarker.hintString != oldHintString)
        linksMatched.push(linkMarker)

    linksMatched

  deactivate: (delay, callback) ->
    @hintKeystrokeQueue = []
    @linkTextKeystrokeQueue = []
    @labelMap = {}

#
# Make each hint character a span, so that we can highlight the typed characters as you type them.
#
spanWrap = (hintString) ->
  innerHTML = []
  for char in hintString
    innerHTML.push("<span class='vimiumReset'>" + char + "</span>")
  innerHTML.join("")

#
# Converts a number like "8" into a hint string like "JK". This is used to sequentially generate all of the
# hint text. The hint string will be "padded with zeroes" to ensure its length is >= numHintDigits.
#
numberToHintString = (number, characterSet, numHintDigits = 0) ->
  base = characterSet.length
  hintString = []
  remainder = 0
  loop
    remainder = number % base
    hintString.unshift(characterSet[remainder])
    number -= remainder
    number /= Math.floor(base)
    break unless number > 0

  # Pad the hint string we're returning so that it matches numHintDigits.
  # Note: the loop body changes hintString.length, so the original length must be cached!
  hintStringLength = hintString.length
  for i in [0...(numHintDigits - hintStringLength)] by 1
    hintString.unshift(characterSet[0])

  hintString.join("")


root = exports ? window
root.LinkHints = LinkHints

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
# The "name" property below is a short-form name to appear in the link-hints mode's name.  It's for debug only.
#
OPEN_IN_CURRENT_TAB = name: "curr-tab"
OPEN_IN_NEW_BG_TAB = name: "bg-tab"
OPEN_IN_NEW_FG_TAB = name: "fg-tab"
OPEN_WITH_QUEUE = name: "queue"
COPY_LINK_URL = name: "link"
OPEN_INCOGNITO = name: "incognito"
DOWNLOAD_LINK_URL = name: "download"

LinkHints =
  activateMode: (mode = OPEN_IN_CURRENT_TAB) -> new LinkHintsMode mode

  activateModeToOpenInNewTab: -> @activateMode OPEN_IN_NEW_BG_TAB
  activateModeToOpenInNewForegroundTab: -> @activateMode OPEN_IN_NEW_FG_TAB
  activateModeToCopyLinkUrl: -> @activateMode COPY_LINK_URL
  activateModeWithQueue: -> @activateMode OPEN_WITH_QUEUE
  activateModeToOpenIncognito: -> @activateMode OPEN_INCOGNITO
  activateModeToDownloadLink: -> @activateMode DOWNLOAD_LINK_URL

class LinkHintsMode
  hintMarkerContainingDiv: null
  # One of the enums listed at the top of this file.
  mode: undefined
  # Function that does the appropriate action on the selected link.
  linkActivator: undefined
  # Lock to ensure only one instance runs at a time.
  isActive: false
  # The link-hints "mode" (in the key-handler, indicator sense).
  hintMode: null
  # Call this function on exit (if defined).
  onExit: null
  # A count of the number of Tab presses since the last non-Tab keyboard event.
  tabCount: 0

  constructor: (mode = OPEN_IN_CURRENT_TAB) ->
    # we need documentElement to be ready in order to append links
    return unless document.documentElement
    @isActive = true

    elements = @getVisibleClickableElements()
    # For these modes, we filter out those elements which don't have an HREF (since there's nothing we can do
    # with them).
    elements = (el for el in elements when el.element.href?) if mode in [ COPY_LINK_URL, OPEN_INCOGNITO ]
    if Settings.get "filterLinkHints"
      # When using text filtering, we sort the elements such that we visit descendants before their ancestors.
      # This allows us to exclude the text used for matching descendants from that used for matching their
      # ancestors.
      length = (el) -> el.element.innerHTML?.length ? 0
      elements.sort (a,b) -> length(a) - length b
    hintMarkers = (@createMarkerFor(el) for el in elements)
    @markerMatcher = new (if Settings.get "filterLinkHints" then FilterHints else AlphabetHints)
    @markerMatcher.fillInMarkers hintMarkers

    @hintMode = new Mode
      name: "hint/#{mode.name}"
      indicator: false
      passInitialKeyupEvents: true
      suppressAllKeyboardEvents: true
      suppressTrailingKeyEvents: true
      exitOnEscape: true
      exitOnClick: true
      exitOnScroll: true
      keydown: @onKeyDownInMode.bind this, hintMarkers
      keypress: @onKeyPressInMode.bind this, hintMarkers

    @hintMode.onExit =>
      @deactivateMode() if @isActive

    @setOpenLinkMode mode

    # Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    # because some clickable elements cannot contain children, e.g. submit buttons.
    @hintMarkerContainingDiv = DomUtils.addElementList hintMarkers,
      id: "vimiumHintMarkerContainer", className: "vimiumReset"

  setOpenLinkMode: (@mode) ->
    if @mode is OPEN_IN_NEW_BG_TAB or @mode is OPEN_IN_NEW_FG_TAB or @mode is OPEN_WITH_QUEUE
      if @mode is OPEN_IN_NEW_BG_TAB
        @hintMode.setIndicator "Open link in new tab."
      else if @mode is OPEN_IN_NEW_FG_TAB
        @hintMode.setIndicator "Open link in new tab and switch to it."
      else
        @hintMode.setIndicator "Open multiple links in new tabs."
      @linkActivator = (link) ->
        # When "clicking" on a link, dispatch the event with the appropriate meta key (CMD on Mac, CTRL on
        # windows) to open it in a new tab if necessary.
        DomUtils.simulateClick link,
          shiftKey: @mode is OPEN_IN_NEW_FG_TAB
          metaKey: KeyboardUtils.platform == "Mac"
          ctrlKey: KeyboardUtils.platform != "Mac"
          altKey: false
    else if @mode is COPY_LINK_URL
      @hintMode.setIndicator "Copy link URL to Clipboard."
      @linkActivator = (link) =>
        if link.href?
          chrome.runtime.sendMessage handler: "copyToClipboard", data: link.href
          url = link.href
          url = url[0..25] + "...." if 28 < url.length
          @onExit = -> HUD.showForDuration "Yanked #{url}", 2000
        else
          @onExit = -> HUD.showForDuration "No link to yank.", 2000
    else if @mode is OPEN_INCOGNITO
      @hintMode.setIndicator "Open link in incognito window."
      @linkActivator = (link) ->
        chrome.runtime.sendMessage handler: 'openUrlInIncognito', url: link.href
    else if @mode is DOWNLOAD_LINK_URL
      @hintMode.setIndicator "Download link URL."
      @linkActivator = (link) ->
        DomUtils.simulateClick link, altKey: true, ctrlKey: false, metaKey: false
    else # OPEN_IN_CURRENT_TAB
      @hintMode.setIndicator "Open link in current tab."
      @linkActivator = (link) -> DomUtils.simulateClick.bind(DomUtils, link)()

  #
  # Creates a link marker for the given link.
  #
  createMarkerFor: do ->
    # This count is used to rank equal-scoring hints when sorting, thereby making JavaScript's sort stable.
    stableSortCount = 0
    (link) ->
      marker = DomUtils.createElement "div"
      marker.className = "vimiumReset internalVimiumHintMarker vimiumHintMarker"
      marker.clickableItem = link.element
      marker.stableSortCount = ++stableSortCount

      clientRect = link.rect
      marker.style.left = clientRect.left + window.scrollX + "px"
      marker.style.top = clientRect.top  + window.scrollY  + "px"

      marker.rect = link.rect

      marker

  #
  # Determine whether the element is visible and clickable. If it is, find the rect bounding the element in
  # the viewport.  There may be more than one part of element which is clickable (for example, if it's an
  # image), therefore we always return a array of element/rect pairs (which may also be a singleton or empty).
  #
  getVisibleClickable: (element) ->
    tagName = element.tagName.toLowerCase()
    isClickable = false
    onlyHasTabIndex = false
    visibleElements = []

    # Insert area elements that provide click functionality to an img.
    if tagName == "img"
      mapName = element.getAttribute "usemap"
      if mapName
        imgClientRects = element.getClientRects()
        mapName = mapName.replace(/^#/, "").replace("\"", "\\\"")
        map = document.querySelector "map[name=\"#{mapName}\"]"
        if map and imgClientRects.length > 0
          areas = map.getElementsByTagName "area"
          areasAndRects = DomUtils.getClientRectsForAreas imgClientRects[0], areas
          visibleElements.push areasAndRects...

    # Check aria properties to see if the element should be ignored.
    if (element.getAttribute("aria-hidden")?.toLowerCase() in ["", "true"] or
        element.getAttribute("aria-disabled")?.toLowerCase() in ["", "true"])
      return [] # This element should never have a link hint.

    # Check for AngularJS listeners on the element.
    @checkForAngularJs ?= do ->
      angularElements = document.getElementsByClassName "ng-scope"
      if angularElements.length == 0
        -> false
      else
        ngAttributes = []
        for prefix in [ '', 'data-', 'x-' ]
          for separator in [ '-', ':', '_' ]
            ngAttributes.push "#{prefix}ng#{separator}click"
        (element) ->
          for attribute in ngAttributes
            return true if element.hasAttribute attribute
          false

    isClickable ||= @checkForAngularJs element

    # Check for attributes that make an element clickable regardless of its tagName.
    if (element.hasAttribute("onclick") or
        element.getAttribute("role")?.toLowerCase() in ["button", "link"] or
        element.getAttribute("class")?.toLowerCase().indexOf("button") >= 0 or
        element.getAttribute("contentEditable")?.toLowerCase() in ["", "contentEditable", "true"])
      isClickable = true

    # Check for jsaction event listeners on the element.
    if element.hasAttribute "jsaction"
      jsactionRules = element.getAttribute("jsaction").split(";")
      for jsactionRule in jsactionRules
        ruleSplit = jsactionRule.split ":"
        isClickable ||= ruleSplit[0] == "click" or (ruleSplit.length == 1 and ruleSplit[0] != "none")

    # Check for tagNames which are natively clickable.
    switch tagName
      when "a"
        isClickable = true
      when "textarea"
        isClickable ||= not element.disabled and not element.readOnly
      when "input"
        isClickable ||= not (element.getAttribute("type")?.toLowerCase() == "hidden" or
                             element.disabled or
                             (element.readOnly and DomUtils.isSelectable element))
      when "button", "select"
        isClickable ||= not element.disabled
      when "label"
        isClickable ||= element.control? and (@getVisibleClickable element.control).length == 0

    # Elements with tabindex are sometimes useful, but usually not. We can treat them as second class
    # citizens when it improves UX, so take special note of them.
    tabIndexValue = element.getAttribute("tabindex")
    tabIndex = if tabIndexValue == "" then 0 else parseInt tabIndexValue
    unless isClickable or isNaN(tabIndex) or tabIndex < 0
      isClickable = onlyHasTabIndex = true

    if isClickable
      clientRect = DomUtils.getVisibleClientRect element, true
      if clientRect != null
        visibleElements.push {element: element, rect: clientRect, secondClassCitizen: onlyHasTabIndex}

    visibleElements

  #
  # Returns all clickable elements that are not hidden and are in the current viewport, along with rectangles
  # at which (parts of) the elements are displayed.
  # In the process, we try to find rects where elements do not overlap so that link hints are unambiguous.
  # Because of this, the rects returned will frequently *NOT* be equivalent to the rects for the whole
  # element.
  #
  getVisibleClickableElements: ->
    elements = document.documentElement.getElementsByTagName "*"
    visibleElements = []

    # The order of elements here is important; they should appear in the order they are in the DOM, so that
    # we can work out which element is on top when multiple elements overlap. Detecting elements in this loop
    # is the sensible, efficient way to ensure this happens.
    # NOTE(mrmr1993): Our previous method (combined XPath and DOM traversal for jsaction) couldn't provide
    # this, so it's necessary to check whether elements are clickable in order, as we do below.
    for element in elements
      visibleElement = @getVisibleClickable element
      visibleElements.push visibleElement...

    # TODO(mrmr1993): Consider z-index. z-index affects behviour as follows:
    #  * The document has a local stacking context.
    #  * An element with z-index specified
    #    - sets its z-order position in the containing stacking context, and
    #    - creates a local stacking context containing its children.
    #  * An element (1) is shown above another element (2) if either
    #    - in the last stacking context which contains both an ancestor of (1) and an ancestor of (2), the
    #      ancestor of (1) has a higher z-index than the ancestor of (2); or
    #    - in the last stacking context which contains both an ancestor of (1) and an ancestor of (2),
    #        + the ancestors of (1) and (2) have equal z-index, and
    #        + the ancestor of (1) appears later in the DOM than the ancestor of (2).
    #
    # Remove rects from elements where another clickable element lies above it.
    nonOverlappingElements = []
    # Traverse the DOM from first to last, since later elements show above earlier elements.
    visibleElements = visibleElements.reverse()
    while visibleElement = visibleElements.pop()
      rects = [visibleElement.rect]
      for {rect: negativeRect} in visibleElements
        # Subtract negativeRect from every rect in rects, and concatenate the arrays of rects that result.
        rects = [].concat (rects.map (rect) -> Rect.subtract rect, negativeRect)...
      if rects.length > 0
        nonOverlappingElements.push {element: visibleElement.element, rect: rects[0]}
      else
        # Every part of the element is covered by some other element, so just insert the whole element's
        # rect. Except for elements with tabIndex set (second class citizens); these are often more trouble
        # than they're worth.
        # TODO(mrmr1993): This is probably the wrong thing to do, but we don't want to stop being able to
        # click some elements that we could click before.
        nonOverlappingElements.push visibleElement unless visibleElement.secondClassCitizen

    nonOverlappingElements

  # Handles <Shift> and <Ctrl>.
  onKeyDownInMode: (hintMarkers, event) ->
    return if event.repeat
    @keydownKeyChar = KeyboardUtils.getKeyChar(event).toLowerCase()

    previousTabCount = @tabCount
    @tabCount = 0

    if event.keyCode in [ keyCodes.shiftKey, keyCodes.ctrlKey ] and
      @mode in [ OPEN_IN_CURRENT_TAB, OPEN_WITH_QUEUE, OPEN_IN_NEW_BG_TAB, OPEN_IN_NEW_FG_TAB ]
        @tabCount = previousTabCount
        # Toggle whether to open the link in a new or current tab.
        previousMode = @mode
        keyCode = event.keyCode

        switch keyCode
          when keyCodes.shiftKey
            @setOpenLinkMode(if @mode is OPEN_IN_CURRENT_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_CURRENT_TAB)
          when keyCodes.ctrlKey
            @setOpenLinkMode(if @mode is OPEN_IN_NEW_FG_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_NEW_FG_TAB)

        handlerStack.push
          keyup: (event) =>
            if event.keyCode == keyCode
              handlerStack.remove()
              @setOpenLinkMode previousMode if @isActive
          blur: (event) =>
            handlerStack.remove()
            @setOpenLinkMode previousMode if @isActive

    else if event.keyCode in [ keyCodes.backspace, keyCodes.deleteKey ]
      if @markerMatcher.popKeyChar()
        @updateVisibleMarkers hintMarkers
      else
        @deactivateMode()

    else if event.keyCode == keyCodes.enter
      # Activate the active hint, if there is one.  Only FilterHints uses an active hint.
      @activateLink @markerMatcher.activeHintMarker if @markerMatcher.activeHintMarker

    else if event.keyCode == keyCodes.tab
      @tabCount = previousTabCount + (if event.shiftKey then -1 else 1)
      @updateVisibleMarkers hintMarkers, @tabCount

    else
      return

    # We've handled the event, so suppress it.
    DomUtils.suppressEvent event

  # Handles normal input.
  onKeyPressInMode: (hintMarkers, event) ->
    return if event.repeat

    keyChar = String.fromCharCode(event.charCode).toLowerCase()
    if keyChar
      @markerMatcher.pushKeyChar keyChar, @keydownKeyChar
      @updateVisibleMarkers hintMarkers

    # We've handled the event, so suppress it.
    DomUtils.suppressEvent event

  updateVisibleMarkers: (hintMarkers, tabCount = 0) ->
    keyResult = @markerMatcher.getMatchingHints hintMarkers, tabCount
    linksMatched = keyResult.linksMatched
    if linksMatched.length == 0
      @deactivateMode()
    else if linksMatched.length == 1
      @activateLink linksMatched[0], keyResult.delay ? 0
    else
      @hideMarker marker for marker in hintMarkers
      @showMarker matched, @markerMatcher.hintKeystrokeQueue.length for matched in linksMatched

  #
  # When only one link hint remains, this function activates it in the appropriate way.
  #
  activateLink: (matchedLink, delay = 0) ->
    clickEl = matchedLink.clickableItem
    if (DomUtils.isSelectable(clickEl))
      DomUtils.simulateSelect(clickEl)
      @deactivateMode delay
    else
      # TODO figure out which other input elements should not receive focus
      if (clickEl.nodeName.toLowerCase() == "input" and clickEl.type not in ["button", "submit"])
        clickEl.focus()
      DomUtils.flashRect(matchedLink.rect)
      @linkActivator(clickEl)
      if @mode is OPEN_WITH_QUEUE
        @deactivateMode delay, -> LinkHints.activateModeWithQueue()
      else
        @deactivateMode delay

  #
  # Shows the marker, highlighting matchingCharCount characters.
  #
  showMarker: (linkMarker, matchingCharCount) ->
    linkMarker.style.display = ""
    for j in [0...linkMarker.childNodes.length]
      if (j < matchingCharCount)
        linkMarker.childNodes[j].classList.add("matchingCharacter")
      else
        linkMarker.childNodes[j].classList.remove("matchingCharacter")

  hideMarker: (linkMarker) -> linkMarker.style.display = "none"

  deactivateMode: (delay = 0, callback = null) ->
    deactivate = =>
      DomUtils.removeElement @hintMarkerContainingDiv if @hintMarkerContainingDiv
      @hintMarkerContainingDiv = null
      @markerMatcher = null
      @isActive = false
      @hintMode?.exit()
      @hintMode = null
      @onExit?()
      @onExit = null
      @tabCount = 0

    if delay
      # Install a mode to block keyboard events if the user is still typing.  The intention is to prevent the
      # user from inadvertently launching Vimium commands when typing the link text.
      new TypingProtector delay, ->
        deactivate()
        callback?()
    else
      # We invoke deactivate() directly (instead of setting a timeout of 0) so that deactivateMode() can be
      # tested synchronously.
      deactivate()
      callback?()

# Use characters for hints, and do not filter links by their text.
class AlphabetHints
  logXOfBase: (x, base) -> Math.log(x) / Math.log(base)

  constructor: ->
    @linkHintCharacters = Settings.get "linkHintCharacters"
    # We use the keyChar from keydown if the link-hint characters are all "a-z0-9".  This is the default
    # settings value, and preserves the legacy behavior (which always used keydown) for users which are
    # familiar with that behavior.  Otherwise, we use keyChar from keypress, which admits non-Latin
    # characters. See #1722.
    @useKeydown = /^[a-z0-9]*$/.test @linkHintCharacters
    @hintKeystrokeQueue = []

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
    # Determine how many digits the link hints will require in the worst case. Usually we do not need
    # all of these digits for every link single hint, so we can show shorter hints for a few of the links.
    digitsNeeded = Math.ceil(@logXOfBase(linkCount, @linkHintCharacters.length))
    # Short hints are the number of hints we can possibly show which are (digitsNeeded - 1) digits in length.
    shortHintCount = Math.floor(
      (Math.pow(@linkHintCharacters.length, digitsNeeded) - linkCount) /
      @linkHintCharacters.length)
    longHintCount = linkCount - shortHintCount

    hintStrings = []

    if (digitsNeeded > 1)
      for i in [0...shortHintCount]
        hintStrings.push(numberToHintString(i, @linkHintCharacters, digitsNeeded - 1))

    start = shortHintCount * @linkHintCharacters.length
    for i in [start...(start + longHintCount)]
      hintStrings.push(numberToHintString(i, @linkHintCharacters, digitsNeeded))

    @shuffleHints(hintStrings, @linkHintCharacters.length)

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

  getMatchingHints: (hintMarkers) ->
    matchString = @hintKeystrokeQueue.join ""
    linksMatched: hintMarkers.filter (linkMarker) -> linkMarker.hintString.startsWith matchString

  pushKeyChar: (keyChar, keydownKeyChar) ->
    @hintKeystrokeQueue.push (if @useKeydown then keydownKeyChar else keyChar)
  popKeyChar: -> @hintKeystrokeQueue.pop()

# Use numbers (usually) for hints, and also filter links by their text.
class FilterHints
  constructor: ->
    @linkHintNumbers = Settings.get "linkHintNumbers"
    @hintKeystrokeQueue = []
    @linkTextKeystrokeQueue = []
    @labelMap = {}
    @activeHintMarker = null

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
    numberToHintString linkHintNumber, @linkHintNumbers.toUpperCase()

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
      linkText = DomUtils.textContent.get element

    { text: linkText, show: showLinkText }

  renderMarker: (marker) ->
    marker.innerHTML = spanWrap(marker.hintString +
        (if marker.showLinkText then ": " + marker.linkText else ""))

  fillInMarkers: (hintMarkers) ->
    @generateLabelMap()
    DomUtils.textContent.reset()
    for marker in hintMarkers
      linkTextObject = @generateLinkText(marker.clickableItem)
      marker.linkText = linkTextObject.text
      marker.showLinkText = linkTextObject.show
      @renderMarker(marker)

    @activeHintMarker = hintMarkers[0]
    @activeHintMarker?.classList.add "vimiumActiveHintMarker"

    # We use @filterLinkHints() here (although we know that all of the hints will match) to fill in the hint
    # strings.  This ensures that we always get hint strings in the same order.
    @filterLinkHints hintMarkers

  getMatchingHints: (hintMarkers, tabCount = 0) ->
    delay = 0

    # At this point, linkTextKeystrokeQueue and hintKeystrokeQueue have been updated to reflect the latest
    # input. use them to filter the link hints accordingly.
    matchString = @hintKeystrokeQueue.join ""
    linksMatched = @filterLinkHints hintMarkers
    linksMatched = linksMatched.filter (linkMarker) -> linkMarker.hintString.startsWith matchString

    if linksMatched.length == 1 && @hintKeystrokeQueue.length == 0 and 0 < @linkTextKeystrokeQueue.length
      # In filter mode, people tend to type out words past the point needed for a unique match. Hence we
      # should avoid passing control back to command mode immediately after a match is found.
      delay = 200

    # Visually highlight of the active hint (that is, the one that will be activated if the user
    # types <Enter>).
    tabCount = ((linksMatched.length * Math.abs tabCount) + tabCount) % linksMatched.length
    @activeHintMarker?.classList.remove "vimiumActiveHintMarker"
    @activeHintMarker = linksMatched[tabCount]
    @activeHintMarker?.classList.add "vimiumActiveHintMarker"

    { linksMatched: linksMatched, delay: delay }

  pushKeyChar: (keyChar, keydownKeyChar) ->
    # For filtered hints, we *always* use the keyChar value from keypress, because there is no obvious and
    # easy-to-understand meaning for choosing one of keyChar or keydownKeyChar (as there is for alphabet
    # hints).
    if 0 <= @linkHintNumbers.indexOf keyChar
      @hintKeystrokeQueue.push keyChar
    else
      # Since we might renumber the hints, we should reset the current hintKeyStrokeQueue.
      @hintKeystrokeQueue = []
      @linkTextKeystrokeQueue.push keyChar

  popKeyChar: ->
    @hintKeystrokeQueue.pop() or @linkTextKeystrokeQueue.pop()

  # Filter link hints by search string, renumbering the hints as necessary.
  filterLinkHints: (hintMarkers) ->
    linkSearchString = @linkTextKeystrokeQueue.join("").trim().toLowerCase()
    do (scoreFunction = @scoreLinkHint linkSearchString) ->
      linkMarker.score = scoreFunction linkMarker for linkMarker in hintMarkers
    hintMarkers = hintMarkers[..].sort (a,b) ->
      if b.score == a.score then b.stableSortCount - a.stableSortCount else b.score - a.score

    linkHintNumber = 1
    for linkMarker in hintMarkers
      continue unless 0 < linkMarker.score
      linkMarker.hintString = @generateHintString linkHintNumber++
      @renderMarker linkMarker
      linkMarker

  # Assign a score to a filter match (higher is better).  We assign a higher score for matches at the start of
  # a word, and a considerably higher score still for matches which are whole words.
  scoreLinkHint: (linkSearchString) ->
    searchWords = linkSearchString.trim().split /\s+/
    (linkMarker) ->
      linkWords = linkMarker.linkWords ?= linkMarker.linkText.trim().toLowerCase().split /\s+/

      searchWordScores =
        for searchWord in searchWords
          linkWordScores =
            for linkWord, idx in linkWords
              if linkWord == searchWord
                if idx == 0 then 8 else 6
              else if linkWord.startsWith searchWord
                if idx == 0 then 4 else 2
              else if 0 <= linkWord.indexOf searchWord
                1
              else
                0
          Math.max linkWordScores...

      addFunc = (a,b) -> a + b
      if 0 in searchWordScores then 0 else searchWordScores.reduce addFunc, 0

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

# Suppress all keyboard events until the user stops typing for sufficiently long.
class TypingProtector extends Mode
  constructor: (delay, callback) ->
    @timer = Utils.setTimeout delay, => @exit()

    handler = (event) =>
      clearTimeout @timer
      @timer = Utils.setTimeout 150, => @exit()

    super
      name: "hint/typing-protector"
      suppressAllKeyboardEvents: true
      keydown: handler
      keypress: handler

    @onExit callback

root = exports ? window
root.LinkHints = LinkHints

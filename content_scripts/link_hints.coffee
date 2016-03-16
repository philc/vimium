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
isMac = KeyboardUtils.platform == "Mac"
OPEN_IN_CURRENT_TAB =
  name: "curr-tab"
  indicator: "Open link in current tab."
OPEN_IN_NEW_BG_TAB =
  name: "bg-tab"
  indicator: "Open link in new tab."
  clickModifiers: metaKey: isMac, ctrlKey: not isMac
OPEN_IN_NEW_FG_TAB =
  name: "fg-tab"
  indicator: "Open link in new tab and switch to it."
  clickModifiers: shiftKey: true, metaKey: isMac, ctrlKey: not isMac
OPEN_WITH_QUEUE =
  name: "queue"
  indicator: "Open multiple links in new tabs."
  clickModifiers: metaKey: isMac, ctrlKey: not isMac
COPY_LINK_URL =
  name: "link"
  indicator: "Copy link URL to Clipboard."
  linkActivator: (link) ->
    if link.href?
      chrome.runtime.sendMessage handler: "copyToClipboard", data: link.href
      url = link.href
      url = url[0..25] + "...." if 28 < url.length
      HUD.showForDuration "Yanked #{url}", 2000
    else
      HUD.showForDuration "No link to yank.", 2000
OPEN_INCOGNITO =
  name: "incognito"
  indicator: "Open link in incognito window."
  linkActivator: (link) -> chrome.runtime.sendMessage handler: 'openUrlInIncognito', url: link.href
DOWNLOAD_LINK_URL =
  name: "download"
  indicator: "Download link URL."
  clickModifiers: altKey: true, ctrlKey: false, metaKey: false

availableModes = [OPEN_IN_CURRENT_TAB, OPEN_IN_NEW_BG_TAB, OPEN_IN_NEW_FG_TAB, OPEN_WITH_QUEUE, COPY_LINK_URL,
  OPEN_INCOGNITO, DOWNLOAD_LINK_URL]

HintCoordinator =
  onExit: []

  sendMessage: (messageType, request = {}) ->
    chrome.runtime.sendMessage extend request, {handler: "linkHintsMessage", messageType, frameId}

  prepareToActivateMode: (mode, onExit) ->
    @onExit = [onExit]
    @sendMessage "prepareToActivateMode", modeIndex: availableModes.indexOf mode

  getHintDescriptors: ->
    @localHints = LocalHints.getLocalHints()
    @sendMessage "postHintDescriptors", hintDescriptors:
      @localHints.map ({rect, linkText, showLinkText, hasHref}, localIndex) ->
        {rect, linkText, showLinkText, hasHref, frameId, localIndex}

  # We activate LinkHintsMode() in every frame and provide every frame with exactly the same hint descriptors.
  # We also propagate the key state between frames.  Therefore, the hint-selection process proceeds in lock
  # step in every frame, and @linkHintsMode is in the same state in every frame.
  activateMode: ({hintDescriptors, modeIndex, originatingFrameId}) ->
    @onExit = [] unless frameId == originatingFrameId
    @linkHintsMode = new LinkHintsMode hintDescriptors, availableModes[modeIndex]

  # The following messages are exchanged between frames while link-hints mode is active.
  updateKeyState: (request) -> @linkHintsMode.updateKeyState request
  setOpenLinkMode: ({modeIndex}) -> @linkHintsMode.setOpenLinkMode availableModes[modeIndex], false
  activateActiveHintMarker: -> @linkHintsMode.activateLink @linkHintsMode.markerMatcher.activeHintMarker
  getLocalHintMarker: (hint) -> if hint.frameId == frameId then @localHints[hint.localIndex] else null

  exit: ->
    @onExit.pop()() while 0 < @onExit.length
    @linkHintsMode = @localHints = null

  deactivate: ->
    @onExit = [=> @linkHintsMode.deactivateMode()]
    @exit()

LinkHints =
  activateMode: (count = 1, mode = OPEN_IN_CURRENT_TAB) ->
    if 0 < count or mode is OPEN_WITH_QUEUE
      HintCoordinator.prepareToActivateMode mode, ->
        # Wait for the next tick to allow the previous mode to exit.  It might yet generate a click event,
        # which would cause our new mode to exit immediately.
        Utils.nextTick -> LinkHints.activateMode count-1, mode

  activateModeToOpenInNewTab: (count) -> @activateMode count, OPEN_IN_NEW_BG_TAB
  activateModeToOpenInNewForegroundTab: (count) -> @activateMode count, OPEN_IN_NEW_FG_TAB
  activateModeToCopyLinkUrl: (count) -> @activateMode count, COPY_LINK_URL
  activateModeWithQueue: -> @activateMode 1, OPEN_WITH_QUEUE
  activateModeToOpenIncognito: (count) -> @activateMode count, OPEN_INCOGNITO
  activateModeToDownloadLink: (count) -> @activateMode count, DOWNLOAD_LINK_URL

class LinkHintsModeBase # This is temporary, because the "visible hints" code is embedded in the hints class.
  hintMarkerContainingDiv: null
  # One of the enums listed at the top of this file.
  mode: undefined
  # Function that does the appropriate action on the selected link.
  linkActivator: undefined
  # The link-hints "mode" (in the key-handler, indicator sense).
  hintMode: null
  # A count of the number of Tab presses since the last non-Tab keyboard event.
  tabCount: 0

  constructor: (elements, mode = OPEN_IN_CURRENT_TAB) ->
    # we need documentElement to be ready in order to append links
    return unless document.documentElement

    # For these modes, we filter out those elements which don't have an HREF (since there's nothing we can do
    # with them).
    elements = (el for el in elements when el.hasHref) if mode in [ COPY_LINK_URL, OPEN_INCOGNITO ]

    if elements.length == 0
      HUD.showForDuration "No links to select.", 2000
      return

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
      keydown: @onKeyDownInMode.bind this, hintMarkers
      keypress: @onKeyPressInMode.bind this, hintMarkers

    @hintMode.onExit (event) =>
      HintCoordinator.sendMessage "deactivate" if event?.type == "click" or (event?.type == "keydown" and
        (KeyboardUtils.isEscape(event) or event.keyCode in [keyCodes.backspace, keyCodes.deleteKey]))

    @setOpenLinkMode mode, false

    # Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    # because some clickable elements cannot contain children, e.g. submit buttons.
    @hintMarkerContainingDiv = DomUtils.addElementList hintMarkers,
      id: "vimiumHintMarkerContainer", className: "vimiumReset"
    @hideMarker hintMarker for hintMarker in hintMarkers when hintMarker.hintDescriptor.frameId != frameId
    @updateKeyState = @updateKeyState.bind this, hintMarkers # TODO(smblott): This can be refactored out.

  setOpenLinkMode: (@mode, shouldPropagateToOtherFrames = true) ->
    @hintMode.setIndicator @mode.indicator if windowIsFocused()
    if shouldPropagateToOtherFrames
      HintCoordinator.sendMessage "setOpenLinkMode", modeIndex: availableModes.indexOf @mode

  #
  # Creates a link marker for the given link.
  #
  createMarkerFor: do ->
    # This count is used to rank equal-scoring hints when sorting, thereby making JavaScript's sort stable.
    stableSortCount = 0
    (link) ->
      marker = DomUtils.createElement "div"
      marker.className = "vimiumReset internalVimiumHintMarker vimiumHintMarker"
      marker.stableSortCount = ++stableSortCount
      # Extract other relevant fields from the hint descriptor. TODO(smblott) "link" here is misleading.
      extend marker,
        {hintDescriptor: link, linkText: link.linkText, showLinkText: link.showLinkText, rect: link.rect}

      clientRect = link.rect
      marker.style.left = clientRect.left + window.scrollX + "px"
      marker.style.top = clientRect.top  + window.scrollY  + "px"

      marker

# TODO(smblott)  This is temporary.  Unfortunately, this code is embedded in the "old" link-hints mode class.
# It should be moved, but it's left here for the moment to help keep the diff clearer.
LocalHints =
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
    reason = null

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
      when "body"
        isClickable ||=
          if element == document.body and not document.hasFocus() and
              window.innerWidth > 3 and window.innerHeight > 3 and
              document.body?.tagName.toLowerCase() != "frameset"
            reason = "Frame."
      when "div", "ol", "ul"
        isClickable ||=
          if Scroller.isScrollableElement element
            reason = "Scroll."

    # Elements with tabindex are sometimes useful, but usually not. We can treat them as second class
    # citizens when it improves UX, so take special note of them.
    tabIndexValue = element.getAttribute("tabindex")
    tabIndex = if tabIndexValue == "" then 0 else parseInt tabIndexValue
    unless isClickable or isNaN(tabIndex) or tabIndex < 0
      isClickable = onlyHasTabIndex = true

    if isClickable
      clientRect = DomUtils.getVisibleClientRect element, true
      if clientRect != null
        visibleElements.push {element: element, rect: clientRect, secondClassCitizen: onlyHasTabIndex, reason}

    visibleElements

  #
  # Returns all clickable elements that are not hidden and are in the current viewport, along with rectangles
  # at which (parts of) the elements are displayed.
  # In the process, we try to find rects where elements do not overlap so that link hints are unambiguous.
  # Because of this, the rects returned will frequently *NOT* be equivalent to the rects for the whole
  # element.
  #
  getLocalHints: ->
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
    localHints = nonOverlappingElements = []
    # Traverse the DOM from first to last, since later elements show above earlier elements.
    visibleElements = visibleElements.reverse()
    while visibleElement = visibleElements.pop()
      rects = [visibleElement.rect]
      for {rect: negativeRect} in visibleElements
        # Subtract negativeRect from every rect in rects, and concatenate the arrays of rects that result.
        rects = [].concat (rects.map (rect) -> Rect.subtract rect, negativeRect)...
      if rects.length > 0
        nonOverlappingElements.push extend visibleElement, rect: rects[0]
      else
        # Every part of the element is covered by some other element, so just insert the whole element's
        # rect. Except for elements with tabIndex set (second class citizens); these are often more trouble
        # than they're worth.
        # TODO(mrmr1993): This is probably the wrong thing to do, but we don't want to stop being able to
        # click some elements that we could click before.
        nonOverlappingElements.push visibleElement unless visibleElement.secondClassCitizen

    hint.hasHref = hint.element.href? for hint in localHints
    if Settings.get "filterLinkHints"
      @withLabelMap (labelMap) =>
        extend hint, @generateLinkText labelMap, hint for hint in localHints
    localHints

  # Generate a map of input element => label text, call a callback with it.
  withLabelMap: (callback) ->
    labelMap = {}
    labels = document.querySelectorAll "label"
    for label in labels
      forElement = label.getAttribute "for"
      if forElement
        labelText = label.textContent.trim()
        # Remove trailing ":" commonly found in labels.
        if labelText[labelText.length-1] == ":"
          labelText = labelText.substr 0, labelText.length-1
        labelMap[forElement] = labelText
    callback labelMap

  generateLinkText: (labelMap, hint) ->
    element = hint.element
    linkText = ""
    showLinkText = false
    # toLowerCase is necessary as html documents return "IMG" and xhtml documents return "img"
    nodeName = element.nodeName.toLowerCase()

    if nodeName == "input"
      if labelMap[element.id]
        linkText = labelMap[element.id]
        showLinkText = true
      else if element.type != "password"
        linkText = element.value
        if not linkText and 'placeholder' of element
          linkText = element.placeholder
    # Check if there is an image embedded in the <a> tag.
    else if nodeName == "a" and not element.textContent.trim() and
        element.firstElementChild and
        element.firstElementChild.nodeName.toLowerCase() == "img"
      linkText = element.firstElementChild.alt || element.firstElementChild.title
      showLinkText = true if linkText
    else if hint.reason?
      linkText = hint.reason
      showLinkText = true
    else
      linkText = (element.textContent.trim() || element.innerHTML.trim())[...512]

    {linkText, showLinkText}

# TODO(smblott) Again, this is temporary.  We need to move the code above out of the "old" link-hints class.
class LinkHintsMode extends LinkHintsModeBase
  constructor: (args...) -> super args...

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

        handlerId = handlerStack.push
          keyup: (event) =>
            if event.keyCode == keyCode
              handlerStack.remove()
              @setOpenLinkMode previousMode
            true # Continue bubbling the event.

        # For some (unknown) reason, we don't always receive the keyup event needed to remove this handler.
        # Therefore, we ensure that it's always removed when hint mode exits.  See #1911 and #1926.
        @hintMode.onExit -> handlerStack.remove handlerId

    else if event.keyCode in [ keyCodes.backspace, keyCodes.deleteKey ]
      if @markerMatcher.popKeyChar()
        @updateVisibleMarkers hintMarkers
      else
        # Exit via @hintMode.exit(), so that the LinkHints.activate() "onExit" callback sees the key event and
        # knows not to restart hints mode.
        @hintMode.exit event

    else if event.keyCode == keyCodes.enter
      # Activate the active hint, if there is one.  Only FilterHints uses an active hint.
      HintCoordinator.sendMessage "activateActiveHintMarker" if @markerMatcher.activeHintMarker

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
    {hintKeystrokeQueue, linkTextKeystrokeQueue} = @markerMatcher
    HintCoordinator.sendMessage "updateKeyState", {hintKeystrokeQueue, linkTextKeystrokeQueue, tabCount}

  updateKeyState: (hintMarkers, {hintKeystrokeQueue, linkTextKeystrokeQueue, tabCount}) ->
    extend @markerMatcher, {hintKeystrokeQueue, linkTextKeystrokeQueue}

    {linksMatched, userMightOverType} = @markerMatcher.getMatchingHints hintMarkers, tabCount
    if linksMatched.length == 0
      @deactivateMode()
    else if linksMatched.length == 1
      @activateLink linksMatched[0], userMightOverType ? false
    else
      @hideMarker marker for marker in hintMarkers
      @showMarker matched, @markerMatcher.hintKeystrokeQueue.length for matched in linksMatched

  # When only one hint remains, activate it in the appropriate way.  The current frame may or may not contain
  # the matched link, and may or may not have the focus.  The resulting four cases are accounted for here by
  # selectively pushing the appropriate HintCoordinator.onExit handlers.
  activateLink: (linkMatched, userMightOverType=false) ->
    @removeHintMarkers()
    clickEl = HintCoordinator.getLocalHintMarker(linkMatched.hintDescriptor)?.element

    if clickEl?
      HintCoordinator.onExit.push =>
        if clickEl == document.body
          Utils.nextTick -> focusThisFrame highlight: true
        else if DomUtils.isSelectable clickEl
          window.focus()
          DomUtils.simulateSelect clickEl
        else
          clickActivator = (modifiers) -> (link) -> DomUtils.simulateClick link, modifiers
          linkActivator = @mode.linkActivator ? clickActivator @mode.clickModifiers
          # TODO: Are there any other input elements which should not receive focus?
          if clickEl.nodeName.toLowerCase() == "input" and clickEl.type not in ["button", "submit"]
            clickEl.focus()
          linkActivator clickEl

    installKeyBoardBlocker = (startKeyboardBlocker) ->
      if linkMatched.hintDescriptor.frameId == frameId
        flashEl = DomUtils.addFlashRect linkMatched.hintDescriptor.rect
        HintCoordinator.onExit.push -> DomUtils.removeElement flashEl

      if document.hasFocus()
        startKeyboardBlocker -> HintCoordinator.sendMessage "exit"

    HintCoordinator.onExit.push => @deactivateMode()
    # If we're using a keyboard blocker, then the frame with the focus sends the "exit" message, otherwise the
    # frame containing the matched link does.
    if userMightOverType and Settings.get "waitForEnterForFilteredHints"
      installKeyBoardBlocker (callback) -> new WaitForEnter callback
    else if userMightOverType
      installKeyBoardBlocker (callback) -> new TypingProtector 200, callback
    else if linkMatched.hintDescriptor.frameId == frameId
      DomUtils.flashRect linkMatched.hintDescriptor.rect
      HintCoordinator.sendMessage "exit"

  #
  # Shows the marker, highlighting matchingCharCount characters.
  #
  showMarker: (linkMarker, matchingCharCount) ->
    return unless linkMarker.hintDescriptor.frameId == frameId
    linkMarker.style.display = ""
    for j in [0...linkMarker.childNodes.length]
      if (j < matchingCharCount)
        linkMarker.childNodes[j].classList.add("matchingCharacter")
      else
        linkMarker.childNodes[j].classList.remove("matchingCharacter")

  hideMarker: (linkMarker) -> linkMarker.style.display = "none"

  deactivateMode: ->
    @removeHintMarkers()
    @hintMode?.exit()

  removeHintMarkers: ->
    DomUtils.removeElement @hintMarkerContainingDiv if @hintMarkerContainingDiv
    @hintMarkerContainingDiv = null

# Use characters for hints, and do not filter links by their text.
class AlphabetHints
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
    hints = [""]
    offset = 0
    while hints.length - offset < linkCount or hints.length == 1
      hint = hints[offset++]
      hints.push ch + hint for ch in @linkHintCharacters
    hints = hints[offset...offset+linkCount]

    # Shuffle the hints so that they're scattered; hints starting with the same character and short hints are
    # spread evenly throughout the array.
    return hints.sort().map (str) -> str.reverse()

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
    @activeHintMarker = null
    # The regexp for splitting typed text and link texts.  We split on sequences of non-word characters and
    # link-hint numbers.
    @splitRegexp = new RegExp "[\\W#{Utils.escapeRegexSpecialCharacters @linkHintNumbers}]+"

  generateHintString: (linkHintNumber) ->
    base = @linkHintNumbers.length
    hint = []
    while 0 < linkHintNumber
      hint.push @linkHintNumbers[Math.floor linkHintNumber % base]
      linkHintNumber = Math.floor linkHintNumber / base
    hint.reverse().join ""

  renderMarker: (marker) ->
    marker.innerHTML = spanWrap(marker.hintString +
        (if marker.showLinkText then ": " + marker.linkText else ""))

  fillInMarkers: (hintMarkers) ->
    @renderMarker marker for marker in hintMarkers

    # We use @filterLinkHints() here (although we know that all of the hints will match) to fill in the hint
    # strings.  This ensures that we always get hint strings in the same order.
    @filterLinkHints hintMarkers

  getMatchingHints: (hintMarkers, tabCount = 0) ->
    # At this point, linkTextKeystrokeQueue and hintKeystrokeQueue have been updated to reflect the latest
    # input. use them to filter the link hints accordingly.
    matchString = @hintKeystrokeQueue.join ""
    linksMatched = @filterLinkHints hintMarkers
    linksMatched = linksMatched.filter (linkMarker) -> linkMarker.hintString.startsWith matchString

    # Visually highlight of the active hint (that is, the one that will be activated if the user
    # types <Enter>).
    tabCount = ((linksMatched.length * Math.abs tabCount) + tabCount) % linksMatched.length
    @activeHintMarker?.classList.remove "vimiumActiveHintMarker"
    @activeHintMarker = linksMatched[tabCount]
    @activeHintMarker?.classList.add "vimiumActiveHintMarker"

    linksMatched: linksMatched
    userMightOverType: @hintKeystrokeQueue.length == 0 and 0 < @linkTextKeystrokeQueue.length

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
    searchWords = linkSearchString.trim().split @splitRegexp
    (linkMarker) =>
      text = linkMarker.linkText.trim()
      linkWords = linkMarker.linkWords ?= text.toLowerCase().split @splitRegexp

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

      if 0 in searchWordScores
        0
      else
        addFunc = (a,b) -> a + b
        score = searchWordScores.reduce addFunc, 0
        # Prefer matches in shorter texts.  To keep things balanced for links without any text, we just weight
        # them as if their length was 50.
        score / Math.log 1 + (text.length || 50)

#
# Make each hint character a span, so that we can highlight the typed characters as you type them.
#
spanWrap = (hintString) ->
  innerHTML = []
  for char in hintString
    innerHTML.push("<span class='vimiumReset'>" + char + "</span>")
  innerHTML.join("")

# Suppress all keyboard events until the user stops typing for sufficiently long.
class TypingProtector extends Mode
  constructor: (delay, callback) ->
    @timer = Utils.setTimeout delay, => @exit()

    resetExitTimer = (event) =>
      clearTimeout @timer
      @timer = Utils.setTimeout delay, => @exit()

    super
      name: "hint/typing-protector"
      suppressAllKeyboardEvents: true
      keydown: resetExitTimer
      keypress: resetExitTimer

    @onExit callback

class WaitForEnter extends Mode
  constructor: (callback) ->
    super
      name: "hint/wait-for-enter"
      suppressAllKeyboardEvents: true
      indicator: "Hit <Enter> to proceed..."

    @push
      keydown: (event) =>
        if event.keyCode == keyCodes.enter
          @exit()
          callback()
          DomUtils.suppressEvent event
        else
          true

root = exports ? window
root.LinkHints = LinkHints
root.HintCoordinator = HintCoordinator
# For tests:
extend root, {LinkHintsMode, LocalHints, AlphabetHints}

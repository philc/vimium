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
  indicator: "Open link in current tab"
OPEN_IN_NEW_BG_TAB =
  name: "bg-tab"
  indicator: "Open link in new tab"
  clickModifiers: metaKey: isMac, ctrlKey: not isMac
OPEN_IN_NEW_FG_TAB =
  name: "fg-tab"
  indicator: "Open link in new tab and switch to it"
  clickModifiers: shiftKey: true, metaKey: isMac, ctrlKey: not isMac
OPEN_WITH_QUEUE =
  name: "queue"
  indicator: "Open multiple links in new tabs"
  clickModifiers: metaKey: isMac, ctrlKey: not isMac
COPY_LINK_URL =
  name: "link"
  indicator: "Copy link URL to Clipboard"
  linkActivator: (link) ->
    if link.href?
      HUD.copyToClipboard link.href
      url = link.href
      url = url[0..25] + "...." if 28 < url.length
      HUD.showForDuration "Yanked #{url}", 2000
    else
      HUD.showForDuration "No link to yank.", 2000
OPEN_INCOGNITO =
  name: "incognito"
  indicator: "Open link in incognito window"
  linkActivator: (link) -> chrome.runtime.sendMessage handler: 'openUrlInIncognito', url: link.href
DOWNLOAD_LINK_URL =
  name: "download"
  indicator: "Download link URL"
  clickModifiers: altKey: true, ctrlKey: false, metaKey: false

availableModes = [OPEN_IN_CURRENT_TAB, OPEN_IN_NEW_BG_TAB, OPEN_IN_NEW_FG_TAB, OPEN_WITH_QUEUE, COPY_LINK_URL,
  OPEN_INCOGNITO, DOWNLOAD_LINK_URL]

HintCoordinator =
  onExit: []
  localHints: null
  suppressKeyboardEvents: null

  sendMessage: (messageType, request = {}) ->
    Frame.postMessage "linkHintsMessage", extend request, {messageType}

  prepareToActivateMode: (mode, onExit) ->
    # We need to communicate with the background page (and other frames) to initiate link-hints mode.  To
    # prevent other Vimium commands from being triggered before link-hints mode is launched, we install a
    # temporary mode to block keyboard events.
    @suppressKeyboardEvents = suppressKeyboardEvents = new SuppressAllKeyboardEvents
      name: "link-hints/suppress-keyboard-events"
      singleton: "link-hints-mode"
      indicator: "Collecting hints..."
      exitOnEscape: true
    # FIXME(smblott) Global link hints is currently insufficiently reliable.  If the mode above is left in
    # place, then Vimium blocks.  As a temporary measure, we install a timer to remove it.
    Utils.setTimeout 1000, -> suppressKeyboardEvents.exit() if suppressKeyboardEvents?.modeIsActive
    @onExit = [onExit]
    @sendMessage "prepareToActivateMode",
      modeIndex: availableModes.indexOf(mode), isVimiumHelpDialog: window.isVimiumHelpDialog

  # Hint descriptors are global.  They include all of the information necessary for each frame to determine
  # whether and when a hint from *any* frame is selected.  They include the following properties:
  #   frameId: the frame id of this hint's local frame
  #   localIndex: the index in @localHints for the full hint descriptor for this hint
  #   linkText: the link's text for filtered hints (this is null for alphabet hints)
  getHintDescriptors: ({modeIndex, isVimiumHelpDialog}) ->
    # Ensure that the document is ready and that the settings are loaded.
    DomUtils.documentReady => Settings.onLoaded =>
      requireHref = availableModes[modeIndex] in [COPY_LINK_URL, OPEN_INCOGNITO]
      # If link hints is launched within the help dialog, then we only offer hints from that frame.  This
      # improves the usability of the help dialog on the options page (particularly for selecting command
      # names).
      @localHints =
        if isVimiumHelpDialog and not window.isVimiumHelpDialog
          []
        else
          LocalHints.getLocalHints requireHref
      @localHintDescriptors = @localHints.map ({linkText}, localIndex) -> {frameId, localIndex, linkText}
      @sendMessage "postHintDescriptors", hintDescriptors: @localHintDescriptors

  # We activate LinkHintsMode() in every frame and provide every frame with exactly the same hint descriptors.
  # We also propagate the key state between frames.  Therefore, the hint-selection process proceeds in lock
  # step in every frame, and @linkHintsMode is in the same state in every frame.
  activateMode: ({hintDescriptors, modeIndex, originatingFrameId}) ->
    # We do not receive the frame's own hint descritors back from the background page.  Instead, we merge them
    # with the hint descriptors from other frames here.
    [hintDescriptors[frameId], @localHintDescriptors] = [@localHintDescriptors, null]
    hintDescriptors = [].concat (hintDescriptors[fId] for fId in (fId for own fId of hintDescriptors).sort())...
    # Ensure that the document is ready and that the settings are loaded.
    DomUtils.documentReady => Settings.onLoaded =>
      @suppressKeyboardEvents.exit() if @suppressKeyboardEvents?.modeIsActive
      @suppressKeyboardEvents = null
      @onExit = [] unless frameId == originatingFrameId
      @linkHintsMode = new LinkHintsMode hintDescriptors, availableModes[modeIndex]

  # The following messages are exchanged between frames while link-hints mode is active.
  updateKeyState: (request) -> @linkHintsMode.updateKeyState request
  rotateHints: -> @linkHintsMode.rotateHints()
  setOpenLinkMode: ({modeIndex}) -> @linkHintsMode.setOpenLinkMode availableModes[modeIndex], false
  activateActiveHintMarker: -> @linkHintsMode.activateLink @linkHintsMode.markerMatcher.activeHintMarker
  getLocalHintMarker: (hint) -> if hint.frameId == frameId then @localHints[hint.localIndex] else null

  exit: ({isSuccess}) ->
    @linkHintsMode?.deactivateMode()
    @onExit.pop() isSuccess while 0 < @onExit.length
    @linkHintsMode = @localHints = null

LinkHints =
  activateMode: (count = 1, {mode}) ->
    mode ?= OPEN_IN_CURRENT_TAB
    if 0 < count or mode is OPEN_WITH_QUEUE
      HintCoordinator.prepareToActivateMode mode, (isSuccess) ->
        if isSuccess
          # Wait for the next tick to allow the previous mode to exit.  It might yet generate a click event,
          # which would cause our new mode to exit immediately.
          Utils.nextTick -> LinkHints.activateMode count-1, {mode}

  activateModeToOpenInNewTab: (count) -> @activateMode count, mode: OPEN_IN_NEW_BG_TAB
  activateModeToOpenInNewForegroundTab: (count) -> @activateMode count, mode: OPEN_IN_NEW_FG_TAB
  activateModeToCopyLinkUrl: (count) -> @activateMode count, mode: COPY_LINK_URL
  activateModeWithQueue: -> @activateMode 1, mode: OPEN_WITH_QUEUE
  activateModeToOpenIncognito: (count) -> @activateMode count, mode: OPEN_INCOGNITO
  activateModeToDownloadLink: (count) -> @activateMode count, mode: DOWNLOAD_LINK_URL

class LinkHintsMode
  hintMarkerContainingDiv: null
  # One of the enums listed at the top of this file.
  mode: undefined
  # Function that does the appropriate action on the selected link.
  linkActivator: undefined
  # The link-hints "mode" (in the key-handler, indicator sense).
  hintMode: null
  # A count of the number of Tab presses since the last non-Tab keyboard event.
  tabCount: 0

  constructor: (hintDescriptors, @mode = OPEN_IN_CURRENT_TAB) ->
    # We need documentElement to be ready in order to append links.
    return unless document.documentElement

    if hintDescriptors.length == 0
      HUD.showForDuration "No links to select.", 2000
      return

    # This count is used to rank equal-scoring hints when sorting, thereby making JavaScript's sort stable.
    @stableSortCount = 0
    @hintMarkers = (@createMarkerFor desc for desc in hintDescriptors)
    @markerMatcher = new (if Settings.get "filterLinkHints" then FilterHints else AlphabetHints)
    @markerMatcher.fillInMarkers @hintMarkers, @.getNextZIndex.bind this

    @hintMode = new Mode
      name: "hint/#{@mode.name}"
      indicator: false
      singleton: "link-hints-mode"
      suppressAllKeyboardEvents: true
      suppressTrailingKeyEvents: true
      exitOnEscape: true
      exitOnClick: true
      keydown: @onKeyDownInMode.bind this

    @hintMode.onExit (event) =>
      if event?.type == "click" or (event?.type == "keydown" and
        (KeyboardUtils.isEscape(event) or KeyboardUtils.isBackspace event))
          HintCoordinator.sendMessage "exit", isSuccess: false

    # Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    # because some clickable elements cannot contain children, e.g. submit buttons.
    @hintMarkerContainingDiv = DomUtils.addElementList (marker for marker in @hintMarkers when marker.isLocalMarker),
      id: "vimiumHintMarkerContainer", className: "vimiumReset"

    @setIndicator()

  setOpenLinkMode: (@mode, shouldPropagateToOtherFrames = true) ->
    if shouldPropagateToOtherFrames
      HintCoordinator.sendMessage "setOpenLinkMode", modeIndex: availableModes.indexOf @mode
    else
      @setIndicator()

  setIndicator: ->
    if windowIsFocused()
      typedCharacters = @markerMatcher.linkTextKeystrokeQueue?.join("") ? ""
      indicator = @mode.indicator + (if typedCharacters then ": \"#{typedCharacters}\"" else "") + "."
      @hintMode.setIndicator indicator

  getNextZIndex: do ->
    # This is the starting z-index value; it produces z-index values which are greater than all of the other
    # z-index values used by Vimium.
    baseZIndex = 2140000000
    -> baseZIndex += 1

  #
  # Creates a link marker for the given link.
  #
  createMarkerFor: (desc) ->
    marker =
      if desc.frameId == frameId
        localHintDescriptor = HintCoordinator.getLocalHintMarker desc
        el = DomUtils.createElement "div"
        el.rect = localHintDescriptor.rect
        el.style.left = el.rect.left + "px"
        el.style.top = el.rect.top  + "px"
        # Each hint marker is assigned a different z-index.
        el.style.zIndex = @getNextZIndex()
        extend el,
          className: "vimiumReset internalVimiumHintMarker vimiumHintMarker"
          showLinkText: localHintDescriptor.showLinkText
          localHintDescriptor: localHintDescriptor
      else
        {}

    extend marker,
      hintDescriptor: desc
      isLocalMarker: desc.frameId == frameId
      linkText: desc.linkText
      stableSortCount: ++@stableSortCount

  # Handles all keyboard events.
  onKeyDownInMode: (event) ->
    return if event.repeat

    # NOTE(smblott) The modifier behaviour here applies only to alphabet hints.
    if event.key in ["Control", "Shift"] and not Settings.get("filterLinkHints") and
      @mode in [ OPEN_IN_CURRENT_TAB, OPEN_WITH_QUEUE, OPEN_IN_NEW_BG_TAB, OPEN_IN_NEW_FG_TAB ]
        # Toggle whether to open the link in a new or current tab.
        previousMode = @mode
        key = event.key

        switch key
          when "Shift"
            @setOpenLinkMode(if @mode is OPEN_IN_CURRENT_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_CURRENT_TAB)
          when "Control"
            @setOpenLinkMode(if @mode is OPEN_IN_NEW_FG_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_NEW_FG_TAB)

        handlerId = @hintMode.push
          keyup: (event) =>
            if event.key == key
              handlerStack.remove()
              @setOpenLinkMode previousMode
            true # Continue bubbling the event.

    else if KeyboardUtils.isBackspace event
      if @markerMatcher.popKeyChar()
        @tabCount = 0
        @updateVisibleMarkers()
      else
        # Exit via @hintMode.exit(), so that the LinkHints.activate() "onExit" callback sees the key event and
        # knows not to restart hints mode.
        @hintMode.exit event

    else if event.key == "Enter"
      # Activate the active hint, if there is one.  Only FilterHints uses an active hint.
      HintCoordinator.sendMessage "activateActiveHintMarker" if @markerMatcher.activeHintMarker

    else if event.key == "Tab"
      if event.shiftKey then @tabCount-- else @tabCount++
      @updateVisibleMarkers()

    else if event.key == " " and @markerMatcher.shouldRotateHints event
      HintCoordinator.sendMessage "rotateHints"

    else
      unless event.repeat
        keyChar =
          if Settings.get "filterLinkHints"
            KeyboardUtils.getKeyChar(event)
          else
            KeyboardUtils.getKeyChar(event).toLowerCase()
        if keyChar
          keyChar = " " if keyChar == "space"
          if keyChar.length == 1
            @tabCount = 0
            @markerMatcher.pushKeyChar keyChar
            @updateVisibleMarkers()
          else
            return handlerStack.suppressPropagation

    handlerStack.suppressEvent

  updateVisibleMarkers: ->
    {hintKeystrokeQueue, linkTextKeystrokeQueue} = @markerMatcher
    HintCoordinator.sendMessage "updateKeyState",
      {hintKeystrokeQueue, linkTextKeystrokeQueue, tabCount: @tabCount}

  updateKeyState: ({hintKeystrokeQueue, linkTextKeystrokeQueue, tabCount}) ->
    extend @markerMatcher, {hintKeystrokeQueue, linkTextKeystrokeQueue}

    {linksMatched, userMightOverType} = @markerMatcher.getMatchingHints @hintMarkers, tabCount, this.getNextZIndex.bind this
    if linksMatched.length == 0
      @deactivateMode()
    else if linksMatched.length == 1
      @activateLink linksMatched[0], userMightOverType
    else
      @hideMarker marker for marker in @hintMarkers
      @showMarker matched, @markerMatcher.hintKeystrokeQueue.length for matched in linksMatched

    @setIndicator()

  # Rotate the hints' z-index values so that hidden hints become visible.
  rotateHints: do ->
    markerOverlapsStack = (marker, stack) ->
      for otherMarker in stack
        return true if Rect.intersects marker.markerRect, otherMarker.markerRect
      false

    ->
      # Get local, visible hint markers.
      localHintMarkers = @hintMarkers.filter (marker) ->
        marker.isLocalMarker and marker.style.display != "none"

      # Fill in the markers' rects, if necessary.
      marker.markerRect ?= marker.getClientRects()[0] for marker in localHintMarkers

      # Calculate the overlapping groups of hints.  We call each group a "stack".  This is O(n^2).
      stacks = []
      for marker in localHintMarkers
        stackForThisMarker = null
        stacks =
          for stack in stacks
            markerOverlapsThisStack = markerOverlapsStack marker, stack
            if markerOverlapsThisStack and not stackForThisMarker?
              # We've found an existing stack for this marker.
              stack.push marker
              stackForThisMarker = stack
            else if markerOverlapsThisStack and stackForThisMarker?
              # This marker overlaps a second (or subsequent) stack; merge that stack into stackForThisMarker
              # and discard it.
              stackForThisMarker.push stack...
              continue # Discard this stack.
            else
              stack # Keep this stack.
        stacks.push [marker] unless stackForThisMarker?

      # Rotate the z-indexes within each stack.
      for stack in stacks
        if 1 < stack.length
          zIndexes = (marker.style.zIndex for marker in stack)
          zIndexes.push zIndexes[0]
          marker.style.zIndex = zIndexes[index + 1] for marker, index in stack

      null # Prevent Coffeescript from building an unnecessary array.

  # When only one hint remains, activate it in the appropriate way.  The current frame may or may not contain
  # the matched link, and may or may not have the focus.  The resulting four cases are accounted for here by
  # selectively pushing the appropriate HintCoordinator.onExit handlers.
  activateLink: (linkMatched, userMightOverType = false) ->
    @removeHintMarkers()

    if linkMatched.isLocalMarker
      localHintDescriptor = linkMatched.localHintDescriptor
      clickEl = localHintDescriptor.element
      HintCoordinator.onExit.push (isSuccess) =>
        if isSuccess
          if localHintDescriptor.reason == "Frame."
            Utils.nextTick -> focusThisFrame highlight: true
          else if localHintDescriptor.reason == "Scroll."
            # Tell the scroller that this is the activated element.
            handlerStack.bubbleEvent "DOMActivate", target: clickEl
          else if localHintDescriptor.reason == "Open."
            clickEl.open = !clickEl.open
          else if DomUtils.isSelectable clickEl
            window.focus()
            DomUtils.simulateSelect clickEl
          else
            clickActivator = (modifiers) -> (link) -> DomUtils.simulateClick link, modifiers
            linkActivator = @mode.linkActivator ? clickActivator @mode.clickModifiers
            # TODO: Are there any other input elements which should not receive focus?
            if clickEl.nodeName.toLowerCase() in ["input", "select"] and clickEl.type not in ["button", "submit"]
              clickEl.focus()
            linkActivator clickEl

    # If flash elements are created, then this function can be used later to remove them.
    removeFlashElements = ->
    if linkMatched.isLocalMarker
      {top: viewportTop, left: viewportLeft} = DomUtils.getViewportTopLeft()
      flashElements = for rect in clickEl.getClientRects()
        DomUtils.addFlashRect Rect.translate rect, viewportLeft, viewportTop
      removeFlashElements = -> DomUtils.removeElement flashEl for flashEl in flashElements

    # If we're using a keyboard blocker, then the frame with the focus sends the "exit" message, otherwise the
    # frame containing the matched link does.
    if userMightOverType
      HintCoordinator.onExit.push removeFlashElements
      if windowIsFocused()
        callback = (isSuccess) -> HintCoordinator.sendMessage "exit", {isSuccess}
        if Settings.get "waitForEnterForFilteredHints"
          new WaitForEnter callback
        else
          new TypingProtector 200, callback
    else if linkMatched.isLocalMarker
      Utils.setTimeout 400, removeFlashElements
      HintCoordinator.sendMessage "exit", isSuccess: true

  #
  # Shows the marker, highlighting matchingCharCount characters.
  #
  showMarker: (linkMarker, matchingCharCount) ->
    return unless linkMarker.isLocalMarker
    linkMarker.style.display = ""
    for j in [0...linkMarker.childNodes.length]
      if (j < matchingCharCount)
        linkMarker.childNodes[j].classList.add("matchingCharacter")
      else
        linkMarker.childNodes[j].classList.remove("matchingCharacter")

  hideMarker: (linkMarker) -> linkMarker.style.display = "none" if linkMarker.isLocalMarker

  deactivateMode: ->
    @removeHintMarkers()
    @hintMode?.exit()

  removeHintMarkers: ->
    DomUtils.removeElement @hintMarkerContainingDiv if @hintMarkerContainingDiv
    @hintMarkerContainingDiv = null

# Use characters for hints, and do not filter links by their text.
class AlphabetHints
  constructor: ->
    @linkHintCharacters = Settings.get("linkHintCharacters").toLowerCase()
    @hintKeystrokeQueue = []

  fillInMarkers: (hintMarkers) ->
    hintStrings = @hintStrings(hintMarkers.length)
    for marker, idx in hintMarkers
      marker.hintString = hintStrings[idx]
      marker.innerHTML = spanWrap(marker.hintString.toUpperCase()) if marker.isLocalMarker

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

  pushKeyChar: (keyChar) ->
    @hintKeystrokeQueue.push keyChar
  popKeyChar: -> @hintKeystrokeQueue.pop()

  # For alphabet hints, <Space> always rotates the hints, regardless of modifiers.
  shouldRotateHints: -> true

# Use characters for hints, and also filter links by their text.
class FilterHints
  constructor: ->
    @linkHintNumbers = Settings.get("linkHintNumbers").toUpperCase()
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
    linkText = marker.linkText
    linkText = "#{linkText[..32]}..." if 35 < linkText.length
    marker.innerHTML = spanWrap(marker.hintString +
        (if marker.showLinkText then ": " + linkText else ""))

  fillInMarkers: (hintMarkers, getNextZIndex) ->
    @renderMarker marker for marker in hintMarkers when marker.isLocalMarker

    # We use @getMatchingHints() here (although we know that all of the hints will match) to get an order on
    # the hints and highlight the first one.
    @getMatchingHints hintMarkers, 0, getNextZIndex

  getMatchingHints: (hintMarkers, tabCount, getNextZIndex) ->
    # At this point, linkTextKeystrokeQueue and hintKeystrokeQueue have been updated to reflect the latest
    # input. Use them to filter the link hints accordingly.
    matchString = @hintKeystrokeQueue.join ""
    linksMatched = @filterLinkHints hintMarkers
    linksMatched = linksMatched.filter (linkMarker) -> linkMarker.hintString.startsWith matchString

    # Visually highlight of the active hint (that is, the one that will be activated if the user
    # types <Enter>).
    tabCount = ((linksMatched.length * Math.abs tabCount) + tabCount) % linksMatched.length
    @activeHintMarker?.classList?.remove "vimiumActiveHintMarker"
    @activeHintMarker = linksMatched[tabCount]
    @activeHintMarker?.classList?.add "vimiumActiveHintMarker"
    @activeHintMarker?.style?.zIndex = getNextZIndex()

    linksMatched: linksMatched
    userMightOverType: @hintKeystrokeQueue.length == 0 and 0 < @linkTextKeystrokeQueue.length

  pushKeyChar: (keyChar) ->
    if 0 <= @linkHintNumbers.indexOf keyChar
      @hintKeystrokeQueue.push keyChar
    else if keyChar.toLowerCase() != keyChar and @linkHintNumbers.toLowerCase() != @linkHintNumbers.toUpperCase()
      # The the keyChar is upper case and the link hint "numbers" contain characters (e.g. [a-zA-Z]).  We don't want
      # some upper-case letters matching hints (above) and some matching text (below), so we ignore such keys.
      return
    # We only accept <Space> and characters which are not used for splitting (e.g. "a", "b", etc., but not "-").
    else if keyChar == " " or not @splitRegexp.test keyChar
      # Since we might renumber the hints, we should reset the current hintKeyStrokeQueue.
      @hintKeystrokeQueue = []
      @linkTextKeystrokeQueue.push keyChar.toLowerCase()

  popKeyChar: ->
    @hintKeystrokeQueue.pop() or @linkTextKeystrokeQueue.pop()

  # Filter link hints by search string, renumbering the hints as necessary.
  filterLinkHints: (hintMarkers) ->
    scoreFunction = @scoreLinkHint @linkTextKeystrokeQueue.join ""
    matchingHintMarkers =
      hintMarkers
        .filter (linkMarker) =>
          linkMarker.score = scoreFunction linkMarker
          0 == @linkTextKeystrokeQueue.length or 0 < linkMarker.score
        .sort (a, b) ->
          if b.score == a.score then b.stableSortCount - a.stableSortCount else b.score - a.score

    if matchingHintMarkers.length == 0 and @hintKeystrokeQueue.length == 0 and 0 < @linkTextKeystrokeQueue.length
      # We don't accept typed text which doesn't match any hints.
      @linkTextKeystrokeQueue.pop()
      @filterLinkHints hintMarkers
    else
      linkHintNumber = 1
      for linkMarker in matchingHintMarkers
        linkMarker.hintString = @generateHintString linkHintNumber++
        @renderMarker linkMarker
        linkMarker

  # Assign a score to a filter match (higher is better).  We assign a higher score for matches at the start of
  # a word, and a considerably higher score still for matches which are whole words.
  scoreLinkHint: (linkSearchString) ->
    searchWords = linkSearchString.trim().toLowerCase().split @splitRegexp
    (linkMarker) =>
      return 0 unless 0 < searchWords.length
      # We only keep non-empty link words.  Empty link words cannot be matched, and leading empty link words
      # disrupt the scoring of matches at the start of the text.
      linkWords = linkMarker.linkWords ?= linkMarker.linkText.toLowerCase().split(@splitRegexp).filter (term) -> term

      searchWordScores =
        for searchWord in searchWords
          linkWordScores =
            for linkWord, idx in linkWords
              position = linkWord.indexOf searchWord
              if position < 0
                0 # No match.
              else if position == 0 and searchWord.length == linkWord.length
                if idx == 0 then 8 else 4 # Whole-word match.
              else if position == 0
                if idx == 0 then 6 else 2 # Match at the start of a word.
              else
                1 # 0 < position; other match.
          Math.max linkWordScores...

      if 0 in searchWordScores
        0
      else
        addFunc = (a,b) -> a + b
        score = searchWordScores.reduce addFunc, 0
        # Prefer matches in shorter texts.  To keep things balanced for links without any text, we just weight
        # them as if their length was 100 (so, quite long).
        score / Math.log 1 + (linkMarker.linkText.length || 100)

  # For filtered hints, we require a modifier (because <Space> on its own is a token separator).
  shouldRotateHints: (event) ->
    event.ctrlKey or event.altKey or event.metaKey or event.shiftKey

#
# Make each hint character a span, so that we can highlight the typed characters as you type them.
#
spanWrap = (hintString) ->
  innerHTML = []
  for char in hintString
    innerHTML.push("<span class='vimiumReset'>" + char + "</span>")
  innerHTML.join("")

LocalHints =
  #
  # Determine whether the element is visible and clickable. If it is, find the rect bounding the element in
  # the viewport.  There may be more than one part of element which is clickable (for example, if it's an
  # image), therefore we always return a array of element/rect pairs (which may also be a singleton or empty).
  #
  getVisibleClickable: (element) ->
    # Get the tag name.  However, `element.tagName` can be an element (not a string, see #2035), so we guard
    # against that.
    tagName = element.tagName.toLowerCase?() ? ""
    isClickable = false
    onlyHasTabIndex = false
    possibleFalsePositive = false
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
    if element.hasAttribute("onclick") or
        (role = element.getAttribute "role") and role.toLowerCase() in [
          "button" , "tab" , "link", "checkbox", "menuitem", "menuitemcheckbox", "menuitemradio"
        ] or
        (contentEditable = element.getAttribute "contentEditable") and
          contentEditable.toLowerCase() in ["", "contenteditable", "true"]
      isClickable = true

    # Check for jsaction event listeners on the element.
    if not isClickable and element.hasAttribute "jsaction"
      jsactionRules = element.getAttribute("jsaction").split(";")
      for jsactionRule in jsactionRules
        ruleSplit = jsactionRule.trim().split ":"
        if 1 <= ruleSplit.length <= 2
          [eventType, namespace, actionName ] =
            if ruleSplit.length == 1
              ["click", ruleSplit[0].trim().split(".")..., "_"]
            else
              [ruleSplit[0], ruleSplit[1].trim().split(".")..., "_"]
          isClickable ||= eventType == "click" and namespace != "none" and actionName != "_"

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
        isClickable ||= element.control? and not element.control.disabled and
                        (@getVisibleClickable element.control).length == 0
      when "body"
        isClickable ||=
          if element == document.body and not windowIsFocused() and
              window.innerWidth > 3 and window.innerHeight > 3 and
              document.body?.tagName.toLowerCase() != "frameset"
            reason = "Frame."
        isClickable ||=
          if element == document.body and windowIsFocused() and Scroller.isScrollableElement element
            reason = "Scroll."
      when "img"
        isClickable ||= element.style.cursor in ["zoom-in", "zoom-out"]
      when "div", "ol", "ul"
        isClickable ||=
          if element.clientHeight < element.scrollHeight and Scroller.isScrollableElement element
            reason = "Scroll."
      when "details"
        isClickable = true
        reason = "Open."

    # NOTE(smblott) Disabled pending resolution of #2997.
    # # Detect elements with "click" listeners installed with `addEventListener()`.
    # isClickable ||= element.hasAttribute "_vimium-has-onclick-listener"

    # An element with a class name containing the text "button" might be clickable.  However, real clickables
    # are often wrapped in elements with such class names.  So, when we find clickables based only on their
    # class name, we mark them as unreliable.
    if not isClickable and 0 <= element.getAttribute("class")?.toLowerCase().indexOf "button"
      possibleFalsePositive = isClickable = true

    # Elements with tabindex are sometimes useful, but usually not. We can treat them as second class
    # citizens when it improves UX, so take special note of them.
    tabIndexValue = element.getAttribute("tabindex")
    tabIndex = if tabIndexValue == "" then 0 else parseInt tabIndexValue
    unless isClickable or isNaN(tabIndex) or tabIndex < 0
      isClickable = onlyHasTabIndex = true

    if isClickable
      clientRect = DomUtils.getVisibleClientRect element, true
      if clientRect != null
        visibleElements.push {element: element, rect: clientRect, secondClassCitizen: onlyHasTabIndex,
          possibleFalsePositive, reason}

    visibleElements

  #
  # Returns all clickable elements that are not hidden and are in the current viewport, along with rectangles
  # at which (parts of) the elements are displayed.
  # In the process, we try to find rects where elements do not overlap so that link hints are unambiguous.
  # Because of this, the rects returned will frequently *NOT* be equivalent to the rects for the whole
  # element.
  #
  getLocalHints: (requireHref) ->
    # We need documentElement to be ready in order to find links.
    return [] unless document.documentElement
    elements = document.documentElement.getElementsByTagName "*"
    visibleElements = []

    # The order of elements here is important; they should appear in the order they are in the DOM, so that
    # we can work out which element is on top when multiple elements overlap. Detecting elements in this loop
    # is the sensible, efficient way to ensure this happens.
    # NOTE(mrmr1993): Our previous method (combined XPath and DOM traversal for jsaction) couldn't provide
    # this, so it's necessary to check whether elements are clickable in order, as we do below.
    for element in elements
      unless requireHref and not element.href
        visibleElement = @getVisibleClickable element
        visibleElements.push visibleElement...

    # Traverse the DOM from descendants to ancestors, so later elements show above earlier elements.
    visibleElements = visibleElements.reverse()

    # Filter out suspected false positives.  A false positive is taken to be an element marked as a possible
    # false positive for which a close descendant is already clickable.  False positives tend to be close
    # together in the DOM, so - to keep the cost down - we only search nearby elements.  NOTE(smblott): The
    # visible elements have already been reversed, so we're visiting descendants before their ancestors.
    descendantsToCheck = [1..3] # This determines how many descendants we're willing to consider.
    visibleElements =
      for element, position in visibleElements
        continue if element.possibleFalsePositive and do ->
          index = Math.max 0, position - 6 # This determines how far back we're willing to look.
          while index < position
            candidateDescendant = visibleElements[index].element
            for _ in descendantsToCheck
              candidateDescendant = candidateDescendant?.parentElement
              return true if candidateDescendant == element.element
            index += 1
          false # This is not a false positive.
        element

    # TODO(mrmr1993): Consider z-index. z-index affects behaviour as follows:
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

    # Position the rects within the window.
    {top, left} = DomUtils.getViewportTopLeft()
    for hint in nonOverlappingElements
      hint.rect.top += top
      hint.rect.left += left

    if Settings.get "filterLinkHints"
      extend hint, @generateLinkText hint for hint in localHints
    localHints

  generateLinkText: (hint) ->
    element = hint.element
    linkText = ""
    showLinkText = false
    # toLowerCase is necessary as html documents return "IMG" and xhtml documents return "img"
    nodeName = element.nodeName.toLowerCase()

    if nodeName == "input"
      if element.labels? and element.labels.length > 0
        linkText = element.labels[0].textContent.trim()
        # Remove trailing ":" commonly found in labels.
        if linkText[linkText.length-1] == ":"
          linkText = linkText[...linkText.length-1]
        showLinkText = true
      else if element.getAttribute("type")?.toLowerCase() == "file"
        linkText = "Choose File"
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
    else if 0 < element.textContent.length
      linkText = element.textContent[...256]
    else if element.hasAttribute "title"
      linkText = element.getAttribute "title"
    else
      linkText = element.innerHTML[...256]

    {linkText: linkText.trim(), showLinkText}

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

    @onExit ->
      callback true # true -> isSuccess.

class WaitForEnter extends Mode
  constructor: (callback) ->
    super
      name: "hint/wait-for-enter"
      suppressAllKeyboardEvents: true
      indicator: "Hit <Enter> to proceed..."

    @push
      keydown: (event) =>
        if event.key == "Enter"
          @exit()
          callback true # true -> isSuccess.
        else if KeyboardUtils.isEscape event
          @exit()
          callback false # false -> isSuccess.

root = exports ? (window.root ?= {})
root.LinkHints = LinkHints
root.HintCoordinator = HintCoordinator
# For tests:
extend root, {LinkHintsMode, LocalHints, AlphabetHints, WaitForEnter}
extend window, root unless exports?

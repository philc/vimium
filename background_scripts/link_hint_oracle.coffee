root = exports ? window

LinkHintOracle =
  hintInformationFromTabId: {} # Map of tabId => hintInformation.
  getMarkerMatcher: ->
    if Settings.get("filterLinkHints") then filterHints else alphabetHints

  manageLinkHints: (request, port) ->
    switch request.name
      when "registerLinkHints"
        LinkHintOracle.registerLinkHints(request, port)
      when "handleKeyDown"
        LinkHintOracle.handleKeyDown(request, port)

  registerLinkHints: (request, port) ->
    tabId = port.sender.tab.id

    # Initialise this tab's hintInformation if we haven't already.
    hintInformation = @hintInformationFromTabId[tabId] ?=
      acceptingLinkHintRegistrations: true
      portsFromFrameIds: {} # Map from frameId => port.
      frameIds: []
      hintVisibles: []
      hintKeystrokeQueue: []
      numberOfHintsFromFrameId: {}
      hintIndexInFrame: []

    {portsFromFrameIds, acceptingLinkHintRegistrations, frameIds} = hintInformation
    portsFromFrameIds[request.frameId] = port

    # If we've already started filtering, just ignore this request, pretend the links don't exist.
    return unless (acceptingLinkHintRegistrations)

    @getMarkerMatcher().updateHintInformation(hintInformation, request.hintInformation, request.frameId)
    hintStrings = @getMarkerMatcher().generateHintStrings(hintInformation)

    hintStringsFromFrameId = {}
    for hintString, i in hintStrings
      frameHintStrings = hintStringsFromFrameId[frameIds[i]] ?= []
      frameHintStrings.push(hintString)

    for frameId, port of portsFromFrameIds
      port.postMessage({name: "setHintStrings", hintStrings: hintStringsFromFrameId[frameId]})


  handleKeyDown: (request, port) ->
    tabId = port.sender.tab.id
    hintInformation = @hintInformationFromTabId[tabId]
    {event} = request

    if (event.keyCode == keyCodes.shiftKey or event.keyCode == keyCodes.ctrlKey)
      # We can't handle this in the background. Tell all the pages to handle these themselves.
      for frameId, port of portsFromFrameIds
        port.postMessage({name: "handleKeyDown", event: event})
      return

    if (KeyboardUtils.isEscape(event))
      @deactivate(hintInformation, tabId)
    else
      # Since the user has pressed a key, we assume that there's already a link hint for the link they want.
      hintInformation.acceptingLinkHintRegistrations = false

      {delay, matched} = keyResult = @getMarkerMatcher().matchHintsByKey(hintInformation, event)
      delay ?= 0

      if (matched.length == 0)
        @deactivate(hintInformation, tabId, delay)
      else if (matched.length == 1)
        @activateLink(hintInformation, tabId, matched[0], delay)
      else
        @updateVisibleHints(hintInformation, keyResult)

  deactivate: (hintInformation, tabId, delay) ->
    for frameId, port of hintInformation.portsFromFrameIds
      port.postMessage({
        name: "deactivate"
        delay: delay
      })
    @cleanup(hintInformation, tabId)

  activateLink: (hintInformation, tabId, match, delay) ->
    {frameIds, portsFromFrameIds, hintIndexInFrame} = hintInformation
    matchedFrame = frameIds[match] or -1
    for frameId, port of portsFromFrameIds
      message = {
        name: "linkActivate"
        delay: delay
      }
      if frameId.toString() is matchedFrame.toString()
        message.match = hintIndexInFrame[match]
      port.postMessage(message)
    @cleanup(hintInformation, tabId)


  updateVisibleHints: (hintInformation, keyResult) ->
    {portsFromFrameIds, hintVisibles, frameIds, hintKeystrokeQueue, hintIndexInFrame} = hintInformation
    {delay, matched, updatedHintStrings} = keyResult

    matchedInfoFromFrameId = {}

    for hintVisible, i in hintVisibles
      matchedInfo = matchedInfoFromFrameId[frameIds[i]] ?= {
        currentIndex: -1
        matched: []
        updatedHintStrings: []
        hintVisibles: []
      }
      hintVisibles[i] = false
      matchedInfoFromFrameId[frameIds[i]].hintVisibles.push(false)
    for match, i in matched
      {
        matched: frameMatched
        updatedHintStrings: frameUpdatedHintStrings
        hintVisibles: frameHintVisibles
      } = matchedInfo = matchedInfoFromFrameId[frameIds[i]]
      idx = hintIndexInFrame[match]

      hintVisibles[match] = true
      frameUpdatedHintStrings.push(updatedHintStrings[i])
      frameMatched.push(idx)
      frameHintVisibles[idx] = true

    for frameId, port of portsFromFrameIds
      matchedInfo = matchedInfoFromFrameId[frameId]
      delete matchedInfo.currentIndex
      port.postMessage({
        name: "updateVisibleHints"
        matchedInfo: matchedInfo
        hintKeystrokeQueue: hintKeystrokeQueue
      })

  cleanup: (hintInformation, tabId) ->
    for frameId, port of hintInformation.portsFromFrameIds
      port.disconnect()
    delete hintInformation.portsFromFrameIds

    delete @hintInformationFromTabId[tabId]

alphabetHints =
  logXOfBase: (x, base) -> Math.log(x) / Math.log(base)

  updateHintInformation: (hintInformation, newHintInformation, frameId) ->
    hintInformation.count ?= 0
    {hintVisibles, frameIds, hintIndexInFrame} = hintInformation
    hintInformation.numberOfHintsFromFrameId[frameId] ?= 0

    {count: newCount} = newHintInformation

    hintInformation.count += newCount
    for i in [1..newCount] by 1
      hintVisibles.push(true)
      frameIds.push(frameId)
      hintIndexInFrame.push(hintInformation.numberOfHintsFromFrameId[frameId]++)

    hintInformation

  generateHintStrings: (hintInformation) ->
    hintInformation.hintStrings = @hintStrings(hintInformation.count)

  #
  # Returns a list of hint strings which will uniquely identify the given number of links. The hint strings
  # may be of different lengths.
  #
  hintStrings: (linkCount) ->
    linkHintCharacters = Settings.get("linkHintCharacters")
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
      for i in [0...shortHintCount] by 1
        hintStrings.push(numberToHintString(i, linkHintCharacters, digitsNeeded - 1))

    start = shortHintCount * linkHintCharacters.length
    for i in [start...(start + longHintCount)] by 1
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

  matchHintsByKey: (hintInformation, event) ->
    {hintKeystrokeQueue, hintStrings} = hintInformation

    # If a shifted-character is typed, treat it as lowerase for the purposes of matching hints.
    keyChar = KeyboardUtils.getKeyChar(event).toLowerCase()

    if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey)
      if (!hintKeystrokeQueue.pop())
        return { matched: [], updatedHintStrings: []}
    else if keyChar
      hintKeystrokeQueue.push(keyChar)

    matchString = hintKeystrokeQueue.join("")
    matched = (i for i in [0..hintInformation.count-1] by 1 when hintStrings[i].indexOf(matchString) == 0)
    updatedHintStrings = (hintStrings[i] for i in matched)
    {
      matched: matched
      updatedHintStrings: updatedHintStrings
    }


filterHints =
  updateHintInformation: (hintInformation, newHintInformation, frameId) ->
    hintInformation.linkTextKeystrokeQueue ?= []
    hintInformation.count ?= 0
    hintInformation.numberOfHintsFromFrameId[frameId] ?= 0
    {
      hintVisibles
      frameIds
      hintIndexInFrame
    } = hintInformation
    hintTexts = hintInformation.hintTexts ?= []
    linkTexts = hintInformation.linkTexts ?= []
    showLinkTexts = hintInformation.showLinkTexts ?= []

    {
      linkTexts: newLinkTexts
      showLinkTexts: newShowLinkTexts
    } = newHintInformation

    for newHintText, i in newLinkTexts
      hintVisibles.push(true)
      frameIds.push(frameId)
      hintIndexInFrame.push(hintInformation.numberOfHintsFromFrameId[frameId]++)
      linkTexts.push(newLinkTexts[i])
      hintTexts.push(@generateHintText(hintTexts.length))
      showLinkTexts.push(newShowLinkTexts[i])

    hintInformation

  generateHintText: (linkHintNumber) ->
    (numberToHintString linkHintNumber + 1, Settings.get "linkHintNumbers").toUpperCase()

  getHintString: (hintText, showLinkText, linkText) ->
    hintText + (if showLinkText then ": " + linkText else "")

  generateHintStrings: (hintInformation) ->
    {hintTexts, linkTexts, showLinkTexts} = hintInformation
    hintStrings = hintInformation.hintStrings = []

    for hintText, i in hintTexts
      linkText = linkTexts[i]
      showLinkText = showLinkTexts[i]
      hintStrings.push(@getHintString(hintText, showLinkText, linkText))

    hintStrings

  matchHintsByKey: (hintInformation, event) ->
    {hintKeystrokeQueue, hintVisibles, hintStrings, linkTextKeystrokeQueue} = hintInformation

    keyChar = KeyboardUtils.getKeyChar(event)
    delay = 0
    userIsTypingLinkText = false

    if (event.keyCode == keyCodes.enter)
      # activate the lowest-numbered link hint that is visible
      for hintVisible, i in hintVisibles
        if (hintVisible)
          return {matched: [i], updatedHintStrings: [i]}
    else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey)
      # backspace clears hint key queue first, then acts on link text key queue.
      # if both queues are empty. exit hinting mode
      if (!hintKeystrokeQueue.pop() && !linkTextKeystrokeQueue.pop())
        return {matched: [], updatedHintStrings: []}
    else if (keyChar)
      if (Settings.get("linkHintNumbers").indexOf(keyChar) >= 0)
        hintKeystrokeQueue.push(keyChar)
      else
        # since we might renumber the hints, the current hintKeystrokeQueue
        # should be rendered invalid (i.e. reset).
        hintKeystrokeQueue = hintInformation.hintKeystrokeQueue = []
        linkTextKeystrokeQueue.push(keyChar)
        userIsTypingLinkText = true

    # at this point, linkTextKeystrokeQueue and hintKeystrokeQueue have been updated to reflect the latest
    # input. use them to filter the link hints accordingly.
    returnObject = @filterLinkHints(hintInformation)

    if (returnObject.matched.length == 1 && userIsTypingLinkText)
      # In filter mode, people tend to type out words past the point
      # needed for a unique match. Hence we should avoid passing
      # control back to command mode immediately after a match is found.
      delay = 200

    returnObject.delay = delay
    returnObject

  #
  # Marks the links that do not match the linkText search string with the 'filtered' DOM property. Renumbers
  # the remainder if necessary.
  #
  filterLinkHints: (hintInformation) ->
    {hintKeystrokeQueue, hintStrings, linkTextKeystrokeQueue, linkTexts, showLinkTexts, hintTexts} =
      hintInformation

    matched = []
    updatedHintStrings = []
    linkSearchString = linkTextKeystrokeQueue.join("").toLowerCase()
    hintSearchString = hintKeystrokeQueue.join("")
    linkTextMatchCounter = 0

    for linkText, i in linkTexts
      continue if (linkText.toLowerCase().indexOf(linkSearchString) == -1)

      newHintText = @generateHintText(linkTextMatchCounter)
      hintTexts[i] = newHintText
      linkTextMatchCounter++
      if (newHintText.indexOf(hintSearchString) == 0)
        matched.push(i)
        updatedHintStrings.push(@getHintString(newHintText, showLinkTexts[i], linkTexts[i]))

    { matched: matched, updatedHintStrings: updatedHintStrings }

  deactivate: (hintInformation) ->

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

root.LinkHintOracle = LinkHintOracle

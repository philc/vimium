findModeQuery = { rawQuery: "", matchCount: 0 }
findModeQueryHasResults = false
findModeAnchorNode = null

class FindMode extends Mode
  constructor: (query = "") ->
    super {name: "FIND"}
    # If this is a new search, show the HUD.
    HUD.show("/") if query == ""
    @update query

  keydown: (event) ->
    if KeyboardUtils.isEscape event
      @handleEscapeForFindMode()

    else if event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey
      @handleDeleteForFindMode()

    else if event.keyCode == keyCodes.enter
      @handleEnterForFindMode()

    else unless event.metaKey or event.ctrlKey or event.altKey
      DomUtils.suppressPropagation(event)
      KeydownEvents.push event
      return Mode.handledEvent

    else
      return Mode.unhandledEvent

    Mode.suppressEvent

  keypress: (event) ->
    # Get the pressed key, unless it's a modifier key.
    keyChar = if event.keyCode > 31 then String.fromCharCode(event.charCode) else ""

    if keyChar
      @handleKeyCharForFindMode keyChar
      Mode.suppressEvent
    else
      Mode.unhandledEvent

  handleKeyCharForFindMode: (keyChar) ->
    @update findModeQuery.rawQuery + keyChar
    performFindInPlace()
    showFindModeHUDForQuery()

  handleEscapeForFindMode: ->
    @deactivate()
    document.body.classList.remove "vimiumFindMode"
    # removing the class does not re-color existing selections. we recreate the current selection so it
    # reverts back to the default color.
    selection = window.getSelection()
    unless selection.isCollapsed
      range = window.getSelection().getRangeAt 0
      window.getSelection().removeAllRanges()
      window.getSelection().addRange range
    focusFoundLink() or selectFoundInputElement()

  handleDeleteForFindMode: ->
    if findModeQuery.rawQuery.length == 0
      @deactivate()
      performFindInPlace()
    else
      @update findModeQuery.rawQuery.substring(0, findModeQuery.rawQuery.length - 1)
      performFindInPlace()
      showFindModeHUDForQuery()

  # <esc> sends us into insert mode if possible, but <cr> puts us in normal mode, even if an input is
  # focused.
  # <esc> corresponds approximately to 'nevermind, I have found it already' while <cr> means 'I want to save
  # this query and do more searches with it'
  handleEnterForFindMode: ->
    @deactivate()
    focusFoundLink()
    # If an input is focused, we still want to drop the user back into normal mode. normalModeForInput is a
    # sub-mode of insert mode (and will exit if the insert mode focus changes, we exit insert mode, or were
    # never in insert mode to start with).
    new NormalModeForInput()
    document.body.classList.add "vimiumFindMode"
    settings.set "findModeRawQuery", findModeQuery.rawQuery

  findAndFocus: (backwards) ->
    query =
      if findModeQuery.isRegex
        getNextQueryFromRegexMatches(if backwards then -1 else 1)
      else
        findModeQuery.parsedQuery

    findModeQueryHasResults =
      executeFind query, {backwards: backwards, caseSensitive: not findModeQuery.ignoreCase}

    unless findModeQueryHasResults
      HUD.showForDuration "No matches for '#{findModeQuery.rawQuery}'", 1000
      return

    elementCanTakeInput = document.activeElement &&
      DomUtils.isSelectable(document.activeElement) &&
      DomUtils.isDescendant(findModeAnchorNode, document.activeElement)
    if elementCanTakeInput
      new NormalModeForInput()
    else if document.activeElement and DomUtils.isSelectable document.activeElement
      # The document's active element doesn't contain the selection, so we should blur it.
      document.activeElement.blur()

    focusFoundLink()

  deactivate: ->
    HUD.hide()
    super()

  update: (query) ->
    return if query == findModeQuery.rawQuery
    if query == "" or query != findModeQuery.rawQuery
      findModeQuery =
        rawQuery: query
      return if query == ""

    # the query can be treated differently (e.g. as a plain string versus regex depending on the presence of
    # escape sequences. '\' is the escape character and needs to be escaped itself to be used as a normal
    # character. here we grep for the relevant escape sequences.
    findModeQuery.isRegex = settings.get 'regexFindMode'
    hasNoIgnoreCaseFlag = false
    findModeQuery.parsedQuery = findModeQuery.rawQuery.replace /\\./g, (match) ->
      switch match
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
    findModeQuery.ignoreCase = not hasNoIgnoreCaseFlag and not Utils.hasUpperCase(findModeQuery.parsedQuery)

    # if we are dealing with a regex, grep for all matches in the text, and then call window.find() on them
    # sequentially so the browser handles the scrolling / text selection.
    if findModeQuery.isRegex
      try
        pattern = new RegExp findModeQuery.parsedQuery, "g" + (if findModeQuery.ignoreCase then "i" else "")
      catch error
        # if we catch a SyntaxError, assume the user is not done typing yet and return quietly
        return
      # innerText will not return the text of hidden elements, and strip out tags while preserving newlines
      text = document.body.innerText
      findModeQuery.regexMatches = text.match pattern
      findModeQuery.activeRegexIndex = 0
      findModeQuery.matchCount = findModeQuery.regexMatches?.length
    # if we are doing a basic plain string match, we still want to grep for matches of the string, so we can
    # show a the number of results. We can grep on document.body.innerText, as it should be indistinguishable
    # from the internal representation used by window.find.
    # NOTE(mrmr1993): This is not true; document.body.innerText does not give the contents of inputs/
    # textareas, giving rise to #1118.
    else
      # escape all special characters, so RegExp just parses the string 'as is'.
      # Taken from http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
      escapeRegExp = /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g
      parsedNonRegexQuery = findModeQuery.parsedQuery.replace escapeRegExp, (char) -> "\\" + char
      pattern = new RegExp parsedNonRegexQuery, "g" + (if findModeQuery.ignoreCase then "i" else "")
      text = document.body.innerText
      findModeQuery.matchCount = text.match(pattern)?.length

performFindInPlace = ->
  cachedScrollX = window.scrollX
  cachedScrollY = window.scrollY

  query = if findModeQuery.isRegex then getNextQueryFromRegexMatches 0 else findModeQuery.parsedQuery

  # Search backwards first to "free up" the current word as eligible for the real forward search. This allows
  # us to search in place without jumping around between matches as the query grows.
  executeFind query, {backwards: true, caseSensitive: !findModeQuery.ignoreCase}

  # We need to restore the scroll position because we might've lost the right position by searching
  # backwards.
  window.scrollTo cachedScrollX, cachedScrollY

  findModeQueryHasResults = executeFind query, {caseSensitive: !findModeQuery.ignoreCase}

  if document.activeElement and DomUtils.isSelectable(document.activeElement) and
     not DomUtils.isDescendant(findModeAnchorNode, document.activeElement)
    # The document's active element doesn't contain the selection, so we should blur it.
    document.activeElement.blur()

# :options is an optional dict. valid parameters are 'caseSensitive' and 'backwards'.
executeFind = (query, options) ->
  options = options || {}

  document.body.classList.add "vimiumFindMode"

  # prevent find from matching its own search query in the HUD
  HUD.hide true
  # ignore the selectionchange event generated by find()
  document.removeEventListener "selectionchange",restoreDefaultSelectionHighlight, true
  result = window.find query, options.caseSensitive, options.backwards, true, false, true, false
  setTimeout(
    -> document.addEventListener "selectionchange", restoreDefaultSelectionHighlight, true
    0)

  # we need to save the anchor node here because <esc> seems to nullify it, regardless of whether we do
  # preventDefault()
  findModeAnchorNode = document.getSelection().anchorNode
  result

restoreDefaultSelectionHighlight = -> document.body.classList.remove "vimiumFindMode"

focusFoundLink = ->
  if  findModeQueryHasResults
    link = getLinkFromSelection()
    link?.focus()

selectFoundInputElement = ->
  # if the found text is in an input element, getSelection().anchorNode will be null, so we use activeElement
  # instead. however, since the last focused element might not be the one currently pointed to by find (e.g.
  # the current one might be disabled and therefore unable to receive focus), we use the approximate
  # heuristic of checking that the last anchor node is an ancestor of our element.
  if findModeQueryHasResults && document.activeElement &&
     DomUtils.isSelectable(document.activeElement) &&
     DomUtils.isDescendant(findModeAnchorNode, document.activeElement)
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

window.performFind = ->
  mostRecentQuery = settings.get("findModeRawQuery") || ""
  findMode = new FindMode mostRecentQuery
  findMode.findAndFocus()
  findMode.deactivate()

window.performBackwardsFind = ->
  mostRecentQuery = settings.get("findModeRawQuery") || ""
  findMode = new FindMode mostRecentQuery
  findMode.findAndFocus true
  findMode.deactivate()

getLinkFromSelection = ->
  node = window.getSelection().anchorNode
  while node and node != document.body
    return node if node.nodeName.toLowerCase() == "a"
    node = node.parentNode
  null

# used by the findAndFollow* functions.
followLink = (linkElement) ->
  if linkElement.nodeName.toLowerCase() == "link"
    window.location.href = linkElement.href
  else
    # if we can click on it, don't simply set location.href: some next/prev links are meant to trigger AJAX
    # calls, like the 'more' button on GitHub's newsfeed.
    linkElement.scrollIntoView()
    linkElement.focus()
    DomUtils.simulateClick linkElement

showFindModeHUDForQuery = ->
  if findModeQueryHasResults or findModeQuery.parsedQuery.length == 0
    HUD.show "/#{findModeQuery.rawQuery} (#{findModeQuery.matchCount} Matches)"
  else
    HUD.show "/#{findModeQuery.rawQuery} (No Matches)"


root = exports ? window
root.FindMode = FindMode

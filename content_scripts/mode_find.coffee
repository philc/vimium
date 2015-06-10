# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved here.

# This prevents unmapped printable characters from being passed through to underlying page; see #1415.  Only
# used by PostFindMode, below.
class SuppressPrintable extends Mode
  constructor: (options) ->
    super options
    handler = (event) => if KeyboardUtils.isPrintable event then @suppressEvent else @continueBubbling
    type = document.getSelection().type

    # We use unshift here, so we see events after normal mode, so we only see unmapped keys.
    @unshift
      _name: "mode-#{@id}/suppress-printable"
      keydown: handler
      keypress: handler
      keyup: (event) =>
        # If the selection type has changed (usually, no longer "Range"), then the user is interacting with
        # the input element, so we get out of the way.  See discussion of option 5c from #1415.
        if document.getSelection().type != type then @exit() else handler event

# When we use find, the selection/focus can land in a focusable/editable element.  In this situation, special
# considerations apply.  We implement three special cases:
#   1. Disable insert mode, because the user hasn't asked to enter insert mode.  We do this by using
#      InsertMode.suppressEvent.
#   2. Prevent unmapped printable keyboard events from propagating to the page; see #1415.  We do this by
#      inheriting from SuppressPrintable.
#   3. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends SuppressPrintable
  constructor: ->
    return unless document.activeElement and DomUtils.isEditable document.activeElement
    element = document.activeElement

    super
      name: "post-find"
      # PostFindMode shares a singleton with the modes launched by focusInput; each displaces the other.
      singleton: element
      exitOnBlur: element
      exitOnClick: true
      keydown: (event) -> InsertMode.suppressEvent event # Always truthy, so always continues bubbling.
      keypress: (event) -> InsertMode.suppressEvent event
      keyup: (event) -> InsertMode.suppressEvent event

    # If the very-next keydown is Escape, then exit immediately, thereby passing subsequent keys to the
    # underlying insert-mode instance.
    @push
      _name: "mode-#{@id}/handle-escape"
      keydown: (event) =>
        if KeyboardUtils.isEscape event
          DomUtils.suppressKeyupAfterEscape handlerStack
          @exit()
          @suppressEvent
        else
          handlerStack.remove()
          @continueBubbling

class FindMode extends Mode
  constructor: (@options = {}) ->
    # Save the selection, so findInPlace can restore it.
    @initialRange = getCurrentRange()
    window.findModeQuery = rawQuery: ""
    if @options.returnToViewport
      @scrollX = window.scrollX
      @scrollY = window.scrollY
    super
      name: "find"
      indicator: false
      exitOnClick: true

    HUD.showFindMode this

  exit: (event) ->
    super()
    handleEscapeForFindMode() if event

  restoreSelection: ->
    range = @initialRange
    selection = getSelection()
    selection.removeAllRanges()
    selection.addRange range

  findInPlace: ->
    # Restore the selection.  That way, we're always searching forward from the same place, so we find the right
    # match as the user adds matching characters, or removes previously-matched characters. See #1434.
    @restoreSelection()
    query = if findModeQuery.isRegex then getNextQueryFromRegexMatches(0) else findModeQuery.parsedQuery
    window.findModeQuery.hasResults = executeFind(query, { caseSensitive: !findModeQuery.ignoreCase })

# should be called whenever rawQuery is modified.
window.updateFindModeQuery = ->
  # the query can be treated differently (e.g. as a plain string versus regex depending on the presence of
  # escape sequences. '\' is the escape character and needs to be escaped itself to be used as a normal
  # character. here we grep for the relevant escape sequences.
  findModeQuery.isRegex = Settings.get 'regexFindMode'
  hasNoIgnoreCaseFlag = false
  findModeQuery.parsedQuery = findModeQuery.rawQuery.replace /(\\{1,2})([rRI]?)/g, (match, slashes, flag) ->
    return match if flag == "" or slashes.length != 1
    switch (flag)
      when "r"
        findModeQuery.isRegex = true
      when "R"
        findModeQuery.isRegex = false
      when "I"
        hasNoIgnoreCaseFlag = true
    ""

  # default to 'smartcase' mode, unless noIgnoreCase is explicitly specified
  findModeQuery.ignoreCase = !hasNoIgnoreCaseFlag && !Utils.hasUpperCase(findModeQuery.parsedQuery)

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
    findModeQuery.matchCount = findModeQuery.regexMatches?.length
  # if we are doing a basic plain string match, we still want to grep for matches of the string, so we can
  # show a the number of results. We can grep on document.body.innerText, as it should be indistinguishable
  # from the internal representation used by window.find.
  else
    # escape all special characters, so RegExp just parses the string 'as is'.
    # Taken from http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
    escapeRegExp = /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g
    parsedNonRegexQuery = findModeQuery.parsedQuery.replace(escapeRegExp, (char) -> "\\" + char)
    pattern = new RegExp(parsedNonRegexQuery, "g" + (if findModeQuery.ignoreCase then "i" else ""))
    text = document.body.innerText
    findModeQuery.matchCount = text.match(pattern)?.length

getCurrentRange = ->
  selection = getSelection()
  if selection.type == "None"
    range = document.createRange()
    range.setStart document.body, 0
    range.setEnd document.body, 0
    range
  else
    selection.collapseToStart() if selection.type == "Range"
    selection.getRangeAt 0

root = exports ? window
root.PostFindMode = PostFindMode
root.FindMode = FindMode

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
    window.findModeQueryHasResults = executeFind(query, { caseSensitive: !findModeQuery.ignoreCase })

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

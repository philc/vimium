# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# This is Used as a sub-class to PostFindMode.  It prevents printable characters from being passed through to
# underlying input element; see #1415.  Note, also, that the "Range" condition in the keyup handler
# implmements option 5c from #1415.
class SuppressPrintable extends Mode
  constructor: (options) ->
    super options
    handler = (event) => if KeyboardUtils.isPrintable event then @suppressEvent else @continueBubbling

    # Note: we use unshift here. We see events *after* normal mode, so we only see unmapped keys.
    @unshift
      _name: "mode-#{@id}/suppressPrintableEvents"
      keydown: handler
      keypress: handler
      keyup: (event) =>
        if document.getSelection().type.toLowerCase() != "range" then @exit() else handler event

# When we use find mode, the selection/focus can land in a focusable/editable element.  In this situation,
# special considerations apply.  We implement three special cases:
#   1. Disable insert mode, because the user hasn't asked to enter insert mode.  We do this by using
#      InsertMode.suppressEvent.
#   2. Prevent printable keyboard events from propagating to the page; see #1415.  We do this by inheriting
#      from SuppressPrintable.
#   3. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends SuppressPrintable
  constructor: (findModeAnchorNode) ->
    element = document.activeElement
    return unless element and DomUtils.isEditable element

    super
      name: "post-find"
      singleton: PostFindMode
      exitOnBlur: element
      exitOnClick: true
      keydown: (event) -> InsertMode.suppressEvent event # Always truthy, so always continues bubbling.
      keypress: (event) -> InsertMode.suppressEvent event
      keyup: (event) -> InsertMode.suppressEvent event

    # If the very-next keydown is Esc, drop immediately into insert mode.
    self = @
    @push
      _name: "mode-#{@id}/handle-escape"
      keydown: (event) ->
        if KeyboardUtils.isEscape event
          DomUtils.suppressKeyupAfterEscape handlerStack
          self.exit()
          false # Suppress event.
        else
          @remove()
          true # Continue bubbling.

  # If PostFindMode is active, then we suppress the "I" badge from insert mode.
  chooseBadge: (badge) -> InsertMode.suppressEvent badge

root = exports ? window
root.PostFindMode = PostFindMode

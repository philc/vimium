# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  In this situation,
# special considerations apply.  We implement three special cases:
#   1. Prevent keyboard events from dropping us unintentionally into insert mode.
#   2. Prevent all printable keypress events on the active element from propagating beyond normal mode.  See
#   #1415. This implements Option 2 from there.
#   3. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends Mode
  constructor: (findModeAnchorNode) ->
    element = document.activeElement

    super
      name: "post-find"
      badge: "N" # Pretend to be normal mode (because we don't want the insert-mode badge).
      # Be a singleton.  That way, we don't have to keep track of any currently-active instance.  Any active
      # instance is automatically deactivated when a new instance is activated.
      singleton: PostFindMode
      exitOnBlur: element
      exitOnClick: true
      keydown: (event) -> InsertMode.suppressEvent event
      keypress: (event) -> InsertMode.suppressEvent event
      keyup: (event) =>
        @alwaysContinueBubbling =>
          if document.getSelection().type != "Range"
            # If the selection is no longer a range, then the user is interacting with the element, so get out
            # of the way and stop suppressing insert mode.  See discussion of Option 5c from #1415.
            @exit()
          else
            InsertMode.suppressEvent event

    return @exit() unless element and findModeAnchorNode

    # Special considerations only arise if the active element can take input.  So, exit immediately if it
    # cannot.
    canTakeInput = DomUtils.isSelectable(element) and DomUtils.isDOMDescendant findModeAnchorNode, element
    canTakeInput ||= element.isContentEditable
    canTakeInput ||= findModeAnchorNode.parentElement?.isContentEditable # FIXME(smblott) This is too specific.
    return @exit() unless canTakeInput

    # If the very-next keydown is Esc, drop immediately into insert mode.
    self = @
    @push
      _name: "mode-#{@id}/handle-escape"
      keydown: (event) ->
        if document.activeElement == element and KeyboardUtils.isEscape event
          DomUtils.suppressKeyupAfterEscape handlerStack
          self.exit()
          false # Suppress event.
        else
          @remove()
          true # Continue bubbling.

    # Prevent printable keyboard events from propagating to to the page; see Option 2 from #1415.
    do =>
      handler = (event) =>
        if event.srcElement == element and KeyboardUtils.isPrintable event
          @suppressEvent
        else
          @continueBubbling

      # Note. We use unshift here, instead of push; therefore we see events *after* normal mode, and so only
      # unmapped keys.
      @unshift
        _name: "mode-#{@id}/suppressPrintableEvents"
        keydown: handler
        keypress: handler
        keyup: handler

root = exports ? window
root.PostFindMode = PostFindMode

# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can land in a focusable/editable element.  In this situation,
# special considerations apply.  We implement three special cases:
#   1. Disable keyboard events in insert mode, because the user hasn't asked to enter insert mode.
#   2. Prevent printable keyboard events from propagating to the page; see #1415.
#   3. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends InputController
  constructor: (findModeAnchorNode) ->
    # Locate the element we need to protect.  In most cases, it's just the active element.
    element =
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement
      else
        # For contentEditable elements, chrome does not focus them, although they are activated by keystrokes.
        # We need to find the element ourselves.
        element = findModeAnchorNode
        element = element.parentElement while element.parentElement?.isContentEditable
        if element.isContentEditable
          if DomUtils.isDOMDescendant element, findModeAnchorNode
            # TODO(smblott).  We shouldn't really need to focus the element, here.  Need to look into why this
            # is necessary.
            element.focus()
            element

    return unless element

    super
      name: "post-find"
      exitOnBlur: element
      exitOnClick: true
      keydown: (event) -> InsertMode.suppressEvent event # Truthy.
      keypress: (event) -> InsertMode.suppressEvent event # Truthy.
      keyup: (event) =>
        @alwaysContinueBubbling =>
          if document.getSelection().type != "Range"
            # If the selection is no longer a range, then the user is interacting with the element, so get out
            # of the way.  See Option 5c from #1415.
            @exit()
          else
            InsertMode.suppressEvent event

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

    # Prevent printable keyboard events from propagating to the page; see #1415.
    do =>
      handler = (event) =>
        if event.srcElement == element and KeyboardUtils.isPrintable event
          @suppressEvent
        else
          @continueBubbling

      # Note. We use unshift here, instead of push.  We see events *after* normal mode, so we only see
      # unmapped keys.
      @unshift
        _name: "mode-#{@id}/suppressPrintableEvents"
        keydown: handler
        keypress: handler
        keyup: handler

  chooseBadge: (badge) ->
    # If PostFindMode is active, then we don't want the "I" badge from insert mode.
    InsertMode.suppressEvent badge

root = exports ? window
root.PostFindMode = PostFindMode

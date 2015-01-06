# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  In this situation,
# PostFindMode handles two special cases:
#   1. Suppress InsertModeTrigger.  This prevents keyboard events from dropping us unintentionaly into insert
#      mode.  Here, this is achieved by inheriting from InsertModeBlocker.
#   2. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends InsertModeBlocker
  constructor: (findModeAnchorNode) ->
    element = document.activeElement

    super element,
      name: "post-find"

    return @exit() unless element and findModeAnchorNode

    # Special cases only arise if the active element is focusable.  So, exit immediately if it is not.
    canTakeInput = DomUtils.isSelectable(element) and DomUtils.isDOMDescendant findModeAnchorNode, element
    canTakeInput ||= element.isContentEditable
    return @exit() unless canTakeInput

    self = @
    @push
      keydown: (event) ->
        if element == document.activeElement and KeyboardUtils.isEscape event
          self.exit()
          new InsertMode element
          return false
        @remove()
        true

    # Install various ways in which we can leave this mode.
    @push
      DOMActive: (event, extra) => @alwaysContinueBubbling => @exit extra
      click: (event, extra) => @alwaysContinueBubbling => @exit extra
      focus: (event, extra) => @alwaysContinueBubbling => @exit extra
      blur: (event, extra) => @alwaysContinueBubbling => @exit extra
      keydown: (event, extra) => @alwaysContinueBubbling => @exit extra if document.activeElement != element

  # Inform handlers further down the stack that PostFindMode exited on this event.
  exit: (extra) ->
    extra.postFindModeExited = true if extra
    super()

root = exports ? window
root.PostFindMode = PostFindMode

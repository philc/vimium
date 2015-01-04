# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  In this situation,
# PostFindMode handles two special cases:
#   1. Suppress InsertModeTrigger.  This presents keyboard events from dropping us unintentionaly into insert
#      mode.  Here, this is achieved by inheriting PostFindMode from InsertModeBlocker.
#   2. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends InsertModeBlocker
  constructor: (findModeAnchorNode) ->
    element = document.activeElement

    super PostFindMode, element,
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
      DOMActive: (event) => handlerStack.alwaysContinueBubbling => @exit()
      click: (event) => handlerStack.alwaysContinueBubbling => @exit()
      focus: (event) => handlerStack.alwaysContinueBubbling => @exit()
      blur: (event) => handlerStack.alwaysContinueBubbling => @exit()
      keydown: (event) => handlerStack.alwaysContinueBubbling => @exit() if document.activeElement != element

root = exports ? window
root.PostFindMode = PostFindMode

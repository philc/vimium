# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  In this situation,
# PostFindMode handles three special cases:
#   1. Be an InsertModeBlocker.  This prevents keyboard events from dropping us unintentionally into insert
#      mode. This is achieved by inheriting from InsertModeBlocker.
#   2. Prevent all keyboard events on the active element from propagating.  This is achieved by setting the
#      trapAllKeyboardEvents option.  There's some controversy as to whether this is the right thing to do.
#      See discussion in #1415. This implements option 2 from there, although option 3 would be a reasonable
#      alternative.
#   3. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends InsertModeBlocker
  constructor: (findModeAnchorNode) ->
    element = document.activeElement

    super
      name: "post-find"
      singleton: PostFindMode
      trapAllKeyboardEvents: element

    return @exit() unless element and findModeAnchorNode

    # Special cases only arise if the active element can take input.  So, exit immediately if it cannot.
    canTakeInput = DomUtils.isSelectable(element) and DomUtils.isDOMDescendant findModeAnchorNode, element
    canTakeInput ||= element.isContentEditable
    canTakeInput ||= findModeAnchorNode.parentElement?.isContentEditable
    return @exit() unless canTakeInput

    self = @
    @push
      keydown: (event) ->
        if element == document.activeElement and KeyboardUtils.isEscape event
          self.exit()
          new InsertMode element
          DomUtils.suppressKeyupAfterEscape handlerStack
          return false
        @remove()
        true

    # Various ways in which we can leave PostFindMode.
    @push
      focus: (event) => @alwaysContinueBubbling => @exit()
      blur: (event) => @alwaysContinueBubbling => @exit()
      keydown: (event) => @alwaysContinueBubbling => @exit() if document.activeElement != element

      # If element is selectable, then it's already focused.  If the user clicks on it, then there's no new
      # focus event, so InsertModeTrigger doesn't fire and we don't drop automatically into insert mode.  So
      # we have to handle this case separately.
      click: (event) =>
        @alwaysContinueBubbling =>
          new InsertMode element if DomUtils.isDOMDescendant element, event.target
          @exit()

root = exports ? window
root.PostFindMode = PostFindMode

# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  In this situation,
# special considerations apply.  We implement two special cases:
#   1. Prevent keyboard events from dropping us unintentionally into insert mode. This is achieved by
#      inheriting from InsertModeBlocker.
#   2. If the very-next keystroke is Escape, then drop immediately into insert mode.
#
class PostFindMode extends InsertModeBlocker
  constructor: (findModeAnchorNode) ->
    element = document.activeElement

    super
      name: "post-find"
      # Be a singleton.  That way, we don't have to keep track of any currently-active instance.  Any active
      # instance is automatically deactivated when a new instance is activated.
      singleton: PostFindMode
      exitOnBlur: element

    return @exit() unless element and findModeAnchorNode

    # Special considerations only arise if the active element can take input.  So, exit immediately if it
    # cannot.
    canTakeInput = DomUtils.isSelectable(element) and DomUtils.isDOMDescendant findModeAnchorNode, element
    canTakeInput ||= element.isContentEditable
    canTakeInput ||= findModeAnchorNode.parentElement?.isContentEditable
    return @exit() unless canTakeInput

    self = @
    @push
      _name: "mode-#{@id}/handle-escape"
      keydown: (event) ->
        if element == document.activeElement and KeyboardUtils.isEscape event
          self.exit()
          new InsertMode
            targetElement: element
          DomUtils.suppressKeyupAfterEscape handlerStack
          return false
        @remove()
        true

root = exports ? window
root.PostFindMode = PostFindMode

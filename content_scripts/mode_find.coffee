# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  Subsequent keyboard
# events could drop us into insert mode, which is a bad user experience.  The PostFindMode mode is installed
# after find events to prevent this.
#
# PostFindMode also maps Esc (on the next keystroke) to immediately drop into insert mode.
class PostFindMode extends SingletonMode
  constructor: (insertMode, findModeAnchorNode) ->
    element = document.activeElement
    return unless element

    # Special cases only arise if the active element is focusable.  So, exit immediately if it is not.
    canTakeInput = DomUtils.isSelectable(element) and DomUtils.isDOMDescendant findModeAnchorNode, element
    canTakeInput ||= element?.isContentEditable
    return unless canTakeInput

    super PostFindMode,
      name: "post-find"

    # If the very next key is Esc, then drop straight into insert mode.
    @push
      keydown: (event) ->
        @remove()
        if element == document.activeElement and KeyboardUtils.isEscape event
          PostFindMode.exitModeAndEnterInsert insertMode, element
          return false
        true

    if element.isContentEditable
      # Prevent InsertMode from activating on keydown.
      @push
        keydown: (event) -> handlerStack.alwaysContinueBubbling -> InsertMode.suppressKeydownTrigger event

    # Install various ways in which we can leave this mode.
    @push
      DOMActive: (event) => handlerStack.alwaysContinueBubbling => @exit()
      click: (event) => handlerStack.alwaysContinueBubbling => @exit()
      focus: (event) => handlerStack.alwaysContinueBubbling => @exit()
      blur: (event) => handlerStack.alwaysContinueBubbling => @exit()
      keydown: (event) => handlerStack.alwaysContinueBubbling => @exit() if document.activeElement != element

  # There's feature interference between PostFindMode, InsertMode and focusInput.  PostFindMode prevents
  # InsertMode from triggering on keyboard events.  And FindMode prevents InsertMode from triggering on focus
  # events.  This means that an input element can already be focused, but InsertMode is not active.  When that
  # element is then (again) focused by focusInput, no new focus event is generated, so we don't drop into
  # InsertMode as expected.
  # This hack fixes this.
  @exitModeAndEnterInsert: (insertMode, element) ->
    SingletonMode.kill PostFindMode
    insertMode.activate insertMode, element

root = exports ? window
root.PostFindMode = PostFindMode

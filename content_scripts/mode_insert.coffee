
# This mode is installed when insert mode is active.
class InsertMode extends Mode
  constructor: (options = {}) ->
    defaults =
      name: "insert"
      badge: "I"
      singleton: InsertMode
      keydown: (event) => @stopBubblingAndTrue
      keypress: (event) => @stopBubblingAndTrue
      keyup: (event) => @stopBubblingAndTrue
      exitOnEscape: true
      blurOnExit: true

    options = extend defaults, options
    options.exitOnBlur = options.targetElement || null
    super options
    triggerSuppressor.suppress()

  exit: (event = null) ->
    triggerSuppressor.unsuppress()
    super()
    if @options.blurOnExit
      element = event?.srcElement
      if element and DomUtils.isFocusable element
        # Remove the focus so the user can't just get himself back into insert mode by typing in the same
        # input box.
        # NOTE(smblott, 2014/12/22) Including embeds for .blur() here is experimental.  It appears to be the
        # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
        # games.  See discussion in #1211 and #1194.
        element.blur()

# Automatically trigger insert mode:
#   - On a keydown event in a contentEditable element.
#   - When a focusable element receives the focus.
#
# The trigger can be suppressed via triggerSuppressor; see InsertModeBlocker, below.
# This mode is permanently installed fairly low down on the handler stack.
class InsertModeTrigger extends Mode
  constructor: ->
    super
      name: "insert-trigger"
      keydown: (event) =>
        triggerSuppressor.unlessSuppressed =>
          # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245);
          # and unfortunately, the focus event happens *before* the change is made.  Therefore, we need to
          # check again whether the active element is contentEditable.
          return @continueBubbling unless document.activeElement?.isContentEditable
          new InsertMode
            targetElement: document.activeElement
          @stopBubblingAndTrue

    @push
      focus: (event) =>
        triggerSuppressor.unlessSuppressed =>
          @alwaysContinueBubbling =>
            if DomUtils.isFocusable event.target
              new InsertMode
                targetElement: event.target

    # We may already have focussed an input, so check.
    if document.activeElement and DomUtils.isEditable document.activeElement
      new InsertMode
        targetElement: document.activeElement

# Used by InsertModeBlocker to suppress InsertModeTrigger; see below.
triggerSuppressor = new Utils.Suppressor true # Note: true == @continueBubbling

# Suppresses InsertModeTrigger.  This is used by various modes (usually by inheritance) to prevent
# unintentionally dropping into insert mode on focusable elements.
class InsertModeBlocker extends Mode
  constructor: (options = {}) ->
    triggerSuppressor.suppress()
    options.name ||= "insert-blocker"
    options.onClickMode ||= InsertMode
    super options
    @onExit -> triggerSuppressor.unsuppress()

    @push
      "click": (event) =>
        @alwaysContinueBubbling =>
          # The user knows best; so, if the user clicks on something, we get out of the way.
          @exit event
          # However, there's a corner case.  If the active element is focusable, then we would have been in
          # insert mode had we not been blocking the trigger.  Now, clicking on the element will not generate
          # a new focus event, so the insert-mode trigger will not fire.  We have to handle this case
          # specially.  @options.onClickMode is the mode to use.
          if document.activeElement and
              event.target == document.activeElement and DomUtils.isEditable document.activeElement
            new @options.onClickMode
              targetElement: document.activeElement

# There's some unfortunate feature interaction with chrome's content editable handling.  If the selection is
# content editable and a descendant of the active element, then chrome focuses it on any unsuppressed keyboard
# events.  This has the unfortunate effect of dropping us unintentally into insert mode.  See #1415.
# This mode sits near the bottom of the handler stack and suppresses keyboard events if:
#   - they haven't been handled by any other mode (so not by normal mode, passkeys mode, insert mode, and so
#     on), and
#   - the selection is content editable, and
#   - the selection is a descendant of the active element.
# This should rarely fire, typically only on fudged keypresses in normal mode.  And, even then, only in the
# circumstances outlined above.  So it shouldn't normally block other extensions or the page itself from
# handling keyboard events.
new class ContentEditableTrap extends Mode
  constructor: ->
    super
      name: "content-editable-trap"
      keydown: (event) => @handle => DomUtils.suppressPropagation event
      keypress: (event) => @handle => @suppressEvent
      keyup: (event) => @handle => @suppressEvent

  # True if the selection is content editable and a descendant of the active element.  In this situation,
  # chrome unilaterally focuses the element containing the anchor, dropping us into insert mode.
  isContentEditableFocused: ->
    element = document.getSelection()?.anchorNode?.parentElement
    return element?.isContentEditable? and
             document.activeElement? and
             DomUtils.isDOMDescendant document.activeElement, element

  handle: (func) ->
    if @isContentEditableFocused() then func() else @continueBubbling

root = exports ? window
root.InsertMode = InsertMode
root.InsertModeTrigger = InsertModeTrigger
root.InsertModeBlocker = InsertModeBlocker

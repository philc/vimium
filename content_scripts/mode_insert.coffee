
# This mode is installed only when insert mode is active.
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
      targetElement: null

    options.exitOnBlur ||= options.targetElement
    super extend defaults, options
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
# The trigger can be suppressed via triggerSuppressor; see InsertModeBlocker, below.  This mode is permanently
# installed (just above normal mode and passkeys mode) on the handler stack.
class InsertModeTrigger extends Mode
  constructor: ->
    super
      name: "insert-trigger"
      keydown: (event) =>
        triggerSuppressor.unlessSuppressed =>
          # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245);
          # and unfortunately, the focus event happens *before* the change is made.  Therefore, we need to
          # check (on every keydown) whether the active element is contentEditable.
          return @continueBubbling unless document.activeElement?.isContentEditable
          new InsertMode
            targetElement: document.activeElement
          @stopBubblingAndTrue

    @push
      _name: "mode-#{@id}/activate-on-focus"
      focus: (event) =>
        triggerSuppressor.unlessSuppressed =>
          @alwaysContinueBubbling =>
            if DomUtils.isFocusable event.target
              new InsertMode
                targetElement: event.target

    # We may have already focussed an input element, so check.
    if document.activeElement and DomUtils.isEditable document.activeElement
      new InsertMode
        targetElement: document.activeElement

# Used by InsertModeBlocker to suppress InsertModeTrigger; see below.
triggerSuppressor = new Utils.Suppressor true # Note: true == @continueBubbling

# Suppresses InsertModeTrigger.  This is used by various modes (usually via inheritance) to prevent
# unintentionally dropping into insert mode on focusable elements.
class InsertModeBlocker extends Mode
  constructor: (options = {}) ->
    triggerSuppressor.suppress()
    options.name ||= "insert-blocker"
    # See "click" handler below for an explanation of options.onClickMode.
    options.onClickMode ||= InsertMode
    super options
    @onExit -> triggerSuppressor.unsuppress()

    @push
      _name: "mode-#{@id}/bail-on-click"
      "click": (event) =>
        @alwaysContinueBubbling =>
          # The user knows best; so, if the user clicks on something, the insert-mode blocker gets out of the
          # way.
          @exit event
          # However, there's a corner case.  If the active element is focusable, then, had we not been
          # blocking the trigger, we would already have been in insert mode.  Now, a click on that element
          # will not generate a new focus event, so the insert-mode trigger will not fire.  We have to handle
          # this case specially.  @options.onClickMode specifies the mode to use (by default, insert mode).
          if document.activeElement and
             event.target == document.activeElement and DomUtils.isEditable document.activeElement
            new @options.onClickMode
              targetElement: document.activeElement

# There's some unfortunate feature interaction with chrome's contentEditable handling.  If the selection is
# contentEditable and a descendant of the active element, then chrome focuses it on any unsuppressed keyboard
# event.  This has the unfortunate effect of dropping us unintentally into insert mode.  See #1415.  A single
# instance of this mode sits near the bottom of the handler stack and suppresses keyboard events if:
#   - they haven't been handled by any other mode (so not by normal mode, passkeys, insert, ...),
#   - the selection is content editable, and
#   - the selection is a descendant of the active element.
# This should rarely fire, typically only on fudged keypresses in normal mode.  And, even then, only in the
# circumstances outlined above.  So, we shouldn't usually be blocking keyboard events for other extensions or
# the page itself.
# There's some controversy as to whether this is the right thing to do.  See discussion in #1415. This
# implements Option 2 from there, although Option 3 would be a reasonable alternative.
new class ContentEditableTrap extends Mode
  constructor: ->
    super
      name: "content-editable-trap"
      keydown: (event) => @handle => DomUtils.suppressPropagation event
      keypress: (event) => @handle => @suppressEvent
      keyup: (event) => @handle => @suppressEvent

  handle: (func) -> if @wouldTriggerInsert() then func() else @continueBubbling

  # True if the selection is content editable and a descendant of the active element.
  wouldTriggerInsert: ->
    element = document.getSelection()?.anchorNode?.parentElement
    return element?.isContentEditable and
             document.activeElement and
             DomUtils.isDOMDescendant document.activeElement, element

root = exports ? window
root.InsertMode = InsertMode
root.InsertModeTrigger = InsertModeTrigger
root.InsertModeBlocker = InsertModeBlocker

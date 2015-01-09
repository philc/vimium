
# This mode is installed when insert mode is active.
class InsertMode extends Mode
  constructor: (@insertModeLock = null) ->
    super
      name: "insert"
      badge: "I"
      singleton: InsertMode
      keydown: (event) => @stopBubblingAndTrue
      keypress: (event) => @stopBubblingAndTrue
      keyup: (event) => @stopBubblingAndTrue
      exitOnEscape: true
      exitOnBlur: @insertModeLock

  exit: (event = null) ->
    super()
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
          new InsertMode document.activeElement
          @stopBubblingAndTrue

    @push
      focus: (event) =>
        triggerSuppressor.unlessSuppressed =>
          return unless DomUtils.isFocusable event.target
          new InsertMode event.target

    # We may already have focussed an input, so check.
    if document.activeElement and DomUtils.isEditable document.activeElement
      new InsertMode document.activeElement

# Used by InsertModeBlocker to suppress InsertModeTrigger; see below.
triggerSuppressor = new Utils.Suppressor true

# Suppresses InsertModeTrigger.  This is used by various modes (usually by inheritance) to prevent
# unintentionally dropping into insert mode on focusable elements.
class InsertModeBlocker extends Mode
  constructor: (options = {}) ->
    triggerSuppressor.suppress()
    options.name ||= "insert-blocker"
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
          # specially.
          if document.activeElement and
              event.target == document.activeElement and DomUtils.isEditable document.activeElement
            new InsertMode document.activeElement

root = exports ? window
root.InsertMode = InsertMode
root.InsertModeTrigger = InsertModeTrigger
root.InsertModeBlocker = InsertModeBlocker

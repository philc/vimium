
class InsertMode extends Mode
  # There is one permanently-installed instance of InsertMode.  It tracks focus changes and
  # activates/deactivates itself (by setting @insertModeLock) accordingly.
  @permanentInstance: null

  constructor: (options = {}) ->
    InsertMode.permanentInstance ||= @
    @permanent = (@ == InsertMode.permanentInstance)

    # If truthy, then we were activated by the user (with "i").
    @global = options.global

    defaults =
      name: "insert"
      keydown: (event) => @handleKeydownEvent event
      keypress: (event) => @handleKeyEvent event
      keyup: (event) => @handleKeyEvent event

    super extend defaults, options

    @insertModeLock =
      if document.activeElement and DomUtils.isEditable document.activeElement
        # An input element is already active, so use it.
        document.activeElement
      else
        null

    @push
      "blur": (event) => @alwaysContinueBubbling =>
        target = event.target
        # We can't rely on focus and blur events arriving in the expected order.  When the active element
        # changes, we might get "focus" before "blur".  We track the active element in @insertModeLock, and
        # exit only when that element blurs.
        @exit event, target if target == @insertModeLock
      "focus": (event) => @alwaysContinueBubbling =>
        if @insertModeLock != event.target and DomUtils.isFocusable event.target
          @insertModeLock = event.target
          Mode.updateBadge()

  isActive: (event) ->
    return false if event == InsertMode.suppressedEvent
    return true if @insertModeLock or @global
    # Some sites (e.g. inbox.google.com) change the contentEditable property on the fly (see #1245); and
    # unfortunately, the focus event fires *before* the change.  Therefore, we need to re-check whether the
    # active element is contentEditable.
    if @insertModeLock != document.activeElement and document.activeElement?.isContentEditable
      @insertModeLock = document.activeElement
      Mode.updateBadge()
    @insertModeLock != null

  handleKeydownEvent: (event) ->
    return @continueBubbling unless @isActive event
    return @stopBubblingAndTrue unless KeyboardUtils.isEscape event
    DomUtils.suppressKeyupAfterEscape handlerStack
    @exit event, event.srcElement
    @suppressEvent

  # Handles keypress and keyup events.
  handleKeyEvent: (event) ->
    if @isActive event then @stopBubblingAndTrue else @continueBubbling

  exit: (_, target)  ->
    if (target and target == @insertModeLock) or @global or target == undefined
      @insertModeLock = null
      if target and DomUtils.isFocusable target
        # Remove the focus, so the user can't just get back into insert mode by typing in the same input box.
        # NOTE(smblott, 2014/12/22) Including embeds for .blur() etc. here is experimental.  It appears to be
        # the right thing to do for most common use cases.  However, it could also cripple flash-based sites and
        # games.  See discussion in #1211 and #1194.
        target.blur()
      # Exit, but only if this isn't the permanently-installed instance.
      if @permanent then Mode.updateBadge() else super()

  updateBadge: (badge) ->
    badge.badge ||= "I" if @isActive badge

  # Static stuff. This allows PostFindMode to suppress the permanently-installed InsertMode instance.
  @suppressedEvent: null
  @suppressEvent: (event) -> @suppressedEvent = event

root = exports ? window
root.InsertMode = InsertMode

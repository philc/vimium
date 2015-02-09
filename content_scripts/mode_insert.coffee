
class InsertMode extends Mode
  constructor: (options = {}) ->
    # There is one permanently-installed instance of InsertMode.  It tracks focus changes and
    # activates/deactivates itself (by setting @insertModeLock) accordingly.
    @permanent = options.permanent

    # If truthy, then we were activated by the user (with "i").
    @global = options.global

    handleKeyEvent = (event) =>
      return @continueBubbling unless @isActive event
      return @stopBubblingAndTrue unless event.type == 'keydown' and KeyboardUtils.isEscape event
      DomUtils.suppressKeyupAfterEscape handlerStack
      target = event.srcElement
      if target and DomUtils.isFocusable target
        # Remove the focus, so the user can't just get back into insert mode by typing in the same input box.
        # NOTE(smblott, 2014/12/22) Including embeds for .blur() etc. here is experimental.  It appears to be
        # the right thing to do for most common use cases.  However, it could also cripple flash-based sites and
        # games.  See discussion in #1211 and #1194.
        target.blur()
      @exit event, event.srcElement
      @suppressEvent

    defaults =
      name: "insert"
      keypress: handleKeyEvent
      keyup: handleKeyEvent
      keydown: handleKeyEvent

    super extend defaults, options

    @insertModeLock =
      if options.targetElement and DomUtils.isEditable options.targetElement
        # The caller has told us which element to activate on.
        options.targetElement
      else if document.activeElement and DomUtils.isEditable document.activeElement
        # An input element is already active, so use it.
        document.activeElement
      else
        null

    @push
      _name: "mode-#{@id}-focus"
      "blur": (event) => @alwaysContinueBubbling =>
        target = event.target
        # We can't rely on focus and blur events arriving in the expected order.  When the active element
        # changes, we might get "focus" before "blur".  We track the active element in @insertModeLock, and
        # exit only when that element blurs.
        # We don't exit if we're running under edit mode.  Edit mode itself will handles that case.
        @exit event, target if @insertModeLock and target == @insertModeLock and not @options.parentMode
      "focus": (event) => @alwaysContinueBubbling =>
        if @insertModeLock != event.target and DomUtils.isFocusable event.target
          @activateOnElement event.target

    # Only for tests.  This gives us a hook to test the status of the permanently-installed instance.
    InsertMode.permanentInstance = @ if @permanent

  isActive: (event) ->
    return false if event == InsertMode.suppressedEvent
    return true if @insertModeLock or @global
    # Some sites (e.g. inbox.google.com) change the contentEditable property on the fly (see #1245); and
    # unfortunately, the focus event fires *before* the change.  Therefore, we need to re-check whether the
    # active element is contentEditable.
    @activateOnElement document.activeElement if document.activeElement?.isContentEditable
    @insertModeLock != null

  activateOnElement: (element) ->
    @log "#{@id}: activating (permanent)" if @debug and @permanent
    @insertModeLock = element
    Mode.updateBadge()

  exit: (_, target)  ->
    if (target and target == @insertModeLock) or @global or target == undefined
      @log "#{@id}: deactivating (permanent)" if @debug and @permanent and @insertModeLock
      @insertModeLock = null
      # Exit, but only if this isn't the permanently-installed instance.
      if @permanent then Mode.updateBadge() else super()

  updateBadge: (badge) ->
    badge.badge ||= @badge if @badge
    badge.badge ||= "I" if @isActive badge

  # Static stuff. This allows PostFindMode to suppress the permanently-installed InsertMode instance.
  @suppressedEvent: null
  @suppressEvent: (event) -> @suppressedEvent = event

root = exports ? window
root.InsertMode = InsertMode

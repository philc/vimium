
class InsertMode extends Mode
  constructor: (options = {}) ->
    # There is one permanently-installed instance of InsertMode.  It tracks focus changes and
    # activates/deactivates itself (by setting @insertModeLock) accordingly.
    @permanent = options.permanent

    # If truthy, then we were activated by the user (with "i").
    if options.global
      @global =
        keyCode: options.global.keyCode || 27
        modifiers: options.global.modifiers || 0

    handleKeyEvent = (event) =>
      return @continueBubbling unless @isActive event
      return @stopBubblingAndTrue unless event.type == 'keydown'
      if @global
        if @global.keyCode != event.keyCode or (event.altKey | (event.ctrlKey << 1) \
            | (event.metaKey << 2) | (event.shiftKey << 3)) != @global.modifiers
          return @stopBubblingAndTrue
      else if not KeyboardUtils.isEscape event
        return @stopBubblingAndTrue
      DomUtils.suppressKeyupAfterEscape handlerStack
      target = event.srcElement
      if target and DomUtils.isFocusable target
        # Remove the focus, so the user can't just get back into insert mode by typing in the same input box.
        target.blur()
      else if target?.shadowRoot and @insertModeLock
        # An editable element in a shadow DOM is focused; blur it.
        @insertModeLock.blur()
      @exit event, event.srcElement
      @suppressEvent

    defaults =
      name: "insert"
      indicator: if @permanent then null else "Insert mode"
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
        else if event.target.shadowRoot
          # A focusable element inside the shadow DOM might have been selected. If so, we can catch the focus
          # event inside the shadow DOM. This fixes #853.
          shadowRoot = event.target.shadowRoot
          eventListeners = {}
          for type in [ "focus", "blur" ]
            eventListeners[type] = do (type) ->
              (event) -> handlerStack.bubbleEvent type, event
            shadowRoot.addEventListener type, eventListeners[type], true

          handlerStack.push
            _name: "shadow-DOM-input-mode"
            blur: (event) ->
              if event.target.shadowRoot == shadowRoot
                handlerStack.remove()
                for type, listener of eventListeners
                  shadowRoot.removeEventListener type, listener, true

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

  exit: (_, target)  ->
    if (target and target == @insertModeLock) or @global or target == undefined
      @log "#{@id}: deactivating (permanent)" if @debug and @permanent and @insertModeLock
      @insertModeLock = null
      # Exit, but only if this isn't the permanently-installed instance.
      super() unless @permanent

  # Static stuff. This allows PostFindMode to suppress the permanently-installed InsertMode instance.
  @suppressedEvent: null
  @suppressEvent: (event) -> @suppressedEvent = event

root = exports ? window
root.InsertMode = InsertMode

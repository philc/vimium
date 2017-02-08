
class InsertMode extends Mode
  constructor: (options = {}) ->
    # There is one permanently-installed instance of InsertMode.  It tracks focus changes and
    # activates/deactivates itself (by setting @insertModeLock) accordingly.
    @permanent = options.permanent

    # If truthy, then we were activated by the user (with "i").
    @global = options.global

    handleKeyEvent = (event) =>
      return @continueBubbling unless @isActive event

      # Check for a pass-next-key key.
      if KeyboardUtils.getKeyCharString(event) in Settings.get "passNextKeyKeys"
        new PassNextKeyMode
        return @suppressEvent

      return @passEventToPage unless event.type == 'keydown' and KeyboardUtils.isEscape event
      target = event.target
      if target and DomUtils.isFocusable target
        # Remove the focus, so the user can't just get back into insert mode by typing in the same input box.
        target.blur()
      else if target?.shadowRoot and @insertModeLock
        # An editable element in a shadow DOM is focused; blur it.
        @insertModeLock.blur()
      @exit event, event.target
      DomUtils.suppressKeyupAfterEscape handlerStack

    defaults =
      name: "insert"
      indicator: if not @permanent and not Settings.get "hideHud"  then "Insert mode"
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
        @exit event, target if @insertModeLock and target == @insertModeLock
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
                for own type, listener of eventListeners
                  shadowRoot.removeEventListener type, listener, true

    # Only for tests.  This gives us a hook to test the status of the permanently-installed instance.
    InsertMode.permanentInstance = this if @permanent

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

# This implements the pasNexKey command.
class PassNextKeyMode extends Mode
  constructor: (count = 1) ->
    seenKeyDown = false
    keyDownCount = 0

    super
      name: "pass-next-key"
      indicator: "Pass next key."
      # We exit on blur because, once we lose the focus, we can no longer track key events.
      exitOnBlur: window
      keypress: =>
        @passEventToPage

      keydown: =>
        seenKeyDown = true
        keyDownCount += 1
        @passEventToPage

      keyup: =>
        if seenKeyDown
          unless 0 < --keyDownCount
            unless 0 < --count
              @exit()
        @passEventToPage

root = exports ? window
root.InsertMode = InsertMode
root.PassNextKeyMode = PassNextKeyMode

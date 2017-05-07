
class InsertMode extends Mode
  constructor: (options = {}) ->
    # There is one permanently-installed instance of InsertMode.  It tracks focus changes and
    # activates/deactivates itself (by setting @insertModeLock) accordingly.
    @permanent = options.permanent

    # If truthy, then we were activated by the user (with "i").
    @global = options.global

    handleKeyEvent = (event) =>
      return @continueBubbling unless @isActive event
      return @passEventToPage if @insertModeLock is document.body

      # Check for a pass-next-key key.
      if KeyboardUtils.getKeyCharString(event) in Settings.get "passNextKeyKeys"
        new PassNextKeyMode
        return @suppressEvent

      return @passEventToPage unless event.type == 'keydown' and KeyboardUtils.isEscape event
      target = event.path?[0] ? event.target
      if target and DomUtils.isFocusable target
        # Remove the focus, so the user can't just get back into insert mode by typing in the same input box.
        target.blur()
      else if target?.shadowRoot and @insertModeLock
        # An editable element in a shadow DOM is focused; blur it.
        @insertModeLock.blur()
      @exit event, target
      DomUtils.consumeKeyup event

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

    @boundShadowRoots = new WeakMap?()

    @push
      _name: "mode-#{@id}-focus"
      "blur": (event) => @alwaysContinueBubbling =>
        target = event.path?[0] ? event.target
        # We can't rely on focus and blur events arriving in the expected order.  When the active element
        # changes, we might get "focus" before "blur".  We track the active element in @insertModeLock, and
        # exit only when that element blurs.
        @exit event, target if @insertModeLock and target == @insertModeLock
      "focus": (event) => @alwaysContinueBubbling =>
        # NOTE(mrmr1993): The first element of event.path gives us the element being focused, even when it is
        # in an (open) shadow DOM.
        target = event.path?[0] ? event.target
        if ShadowRoot?
          shadowRoots = event.path?.filter (node) -> node instanceof ShadowRoot
        if @insertModeLock != target and DomUtils.isFocusable target
          @activateOnElement target
        else if shadowRoots?.length > 0
          # A focusable element inside the shadow DOM has been selected. We catch subsequent focus and blur
          # events inside the shadow DOM. This fixes #853.
          eventListeners = []
          for shadowRoot in shadowRoots
            # Use the following check so we don't get into an infinite loop.
            continue if @boundShadowRoots.has shadowRoot
            @boundShadowRoots.set shadowRoot, true
            do (shadowRoot) =>

              # Capture events inside the shadow DOM.
              # NOTE(mrmr1993): A change of focus between two focusable elements only triggers an event as
              # far out as their outermost shadow DOM common ancestor.
              # - We bubble events from each of these so that we don't miss any relevant change of focus.
              # - The handler pushed onto the stack below will remove all listeners on child shadow DOMs, so:
              #   * we only handle 1 blur event (and thus 1 corresponding focus event).
              #   * we have handlers exactly as deep into nested shadow DOMs as the current focus, and no
              #     further.
              #   * we don't duplicate handlers, fixing #2505.
              eventListeners = {}
              for type in [ "focus", "blur" ]
                eventListeners[type] = do (type) ->
                  (event) -> handlerStack.bubbleEvent type, event
                shadowRoot.addEventListener type, eventListeners[type], true

              handlerStack.push
                _name: "shadow-DOM-input-mode"
                blur: (event) =>
                  if event.path?
                    eventOutsideShadow =
                      event.path.indexOf(shadowRoot) >= 0 and
                      event.path.indexOf(event.currentTarget) > event.path.indexOf(shadowRoot)
                  if eventOutsideShadow ? true
                    @boundShadowRoots.delete shadowRoot
                    handlerStack.remove()
                    for own type, listener of eventListeners
                      shadowRoot.removeEventListener type, listener, true
                  return handlerStack.continueBubbling

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

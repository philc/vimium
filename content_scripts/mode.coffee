#
# A mode implements a number of keyboard event handlers which are pushed onto the handler stack when the mode
# is activated, and popped off when it is deactivated.  The Mode class constructor takes a single argument,
# options, which can define (amongst other things):
#
# name:
#   A name for this mode.
#
# badge:
#   A badge (to appear on the browser popup).
#   Optional.  Define a badge if the badge is constant; for example, in insert mode the badge is always "I".
#   Otherwise, do not define a badge, but instead override the chooseBadge method; for example, in passkeys
#   mode, the badge may be "P" or "", depending on the configuration state.  Or, if the mode *never* shows a
#   badge, then do neither.
#
# keydown:
# keypress:
# keyup:
#   Key handlers.  Optional: provide these as required.  The default is to continue bubbling all key events.
#
# Further options are described in the constructor, below.
#
# Additional handlers associated with a mode can be added by using the push method.  For example, if a mode
# responds to "focus" events, then push an additional handler:
#   @push
#     "focus": (event) => ....
# Any such handlers are removed when the mode is deactivated.
#
# To activate a mode, use:
#   myMode = new MyMode()
#
# Or (usually better) just:
#   new MyMode()
# It is usually not necessary to retain a reference to the mode object.
#
# To deactivate a mode, use:
#   @exit()       # internally triggered (more common).
#   myMode.exit() # externally triggered.
#

# For debug only.
count = 0

class Mode
  # If Mode.debug is true, then we generate a trace of modes being activated and deactivated on the console, along
  # with a list of the currently active modes.
  debug: true
  @modes: []

  # Constants; short, readable names for handlerStack event-handler return values.
  continueBubbling: true
  suppressEvent: false
  stopBubblingAndTrue: handlerStack.stopBubblingAndTrue
  stopBubblingAndFalse: handlerStack.stopBubblingAndFalse
  restartBubbling: handlerStack.restartBubbling

  constructor: (@options={}) ->
    @handlers = []
    @exitHandlers = []
    @modeIsActive = true
    @badge = @options.badge || ""
    @name = @options.name || "anonymous"

    @count = ++count
    @id = "#{@name}-#{@count}"
    @log "activate:", @id if @debug

    @push
      keydown: @options.keydown || null
      keypress: @options.keypress || null
      keyup: @options.keyup || null
      updateBadge: (badge) => @alwaysContinueBubbling => @chooseBadge badge

    # Some modes are singletons: there may be at most one instance active at any one time.  A mode is a
    # singleton if @options.singleton is truthy.  The value of @options.singleton should be the key which is
    # required to be unique.  See PostFindMode for an example.
    # New instances deactivate existing instances as they themselves are activated.
    @registerSingleton @options.singleton if @options.singleton

    # If @options.exitOnEscape is truthy, then the mode will exit when the escape key is pressed.  The
    # triggering keyboard event will be passed to the mode's @exit() method.
    if @options.exitOnEscape
      # Note. This handler ends up above the mode's own key handlers on the handler stack, so it takes
      # priority.
      @push
        _name: "mode-#{@id}/exitOnEscape"
        "keydown": (event) =>
          return @continueBubbling unless KeyboardUtils.isEscape event
          @exit event
          DomUtils.suppressKeyupAfterEscape handlerStack
          @suppressEvent

    # If @options.exitOnBlur is truthy, then it should be an element.  The mode will exit when that element
    # loses the focus.
    if @options.exitOnBlur
      @push
        _name: "mode-#{@id}/exitOnBlur"
        "blur": (event) => @alwaysContinueBubbling => @exit() if event.srcElement == @options.exitOnBlur

    # If @options.exitOnClick is truthy, then the mode will exit on any click event.
    if @options.exitOnClick
      @push
        _name: "mode-#{@id}/exitOnClick"
        "click": (event) => @alwaysContinueBubbling =>
          @clickEvent = event
          @exit()

    # If @options.trackState is truthy, then the mode mainatins the current state in @enabled and @passKeys,
    # and calls @registerStateChange() (if defined) whenever the state changes.
    if @options.trackState
      @enabled = false
      @passKeys = ""
      @push
        _name: "mode-#{@id}/registerStateChange"
        "registerStateChange": ({ enabled: enabled, passKeys: passKeys }) =>
          @alwaysContinueBubbling =>
            if enabled != @enabled or passKeys != @passKeys
              @enabled = enabled
              @passKeys = passKeys
              @registerStateChange?()

    # If @options.suppressPrintableEvents is truthy, then it should be an element.  All printable keyboard
    # events on that element are suppressed, if necessary.  They are suppressed *after* bubbling down the
    # handler stack and finding no handler.  This is used by PostFindMode to protect active, editable
    # elements.  Note, this handler is installed with unshift (not push), so it ends is installed at the
    # *bottom* of the handler stack, and sees keyboard events only after other modes (notably, normal mode)
    # have not handled them.
    if @options.suppressPrintableEvents
      do =>
        handler = (event) =>
          if event.srcElement == @options.suppressPrintableEvents and KeyboardUtils.isPrintable event
            @suppressEvent
          else
            @continueBubbling

        @unshift
          _name: "mode-#{@id}/suppressPrintableEvents"
          keydown: handler
          keypress: handler
          keyup: handler

    Mode.updateBadge() if @badge
    Mode.modes.push @
    @logStack() if @debug
    # handlerStack.debugOn()
    # End of Mode constructor.

  push: (handlers) ->
    handlers._name ||= "mode-#{@id}"
    @handlers.push handlerStack.push handlers

  unshift: (handlers) ->
    handlers._name ||= "mode-#{@id}"
    handlers._name += "/unshifted"
    @handlers.push handlerStack.unshift handlers

  onExit: (handler) ->
    @exitHandlers.push handler

  exit: ->
    if @modeIsActive
      @log "deactivate:", @id if @debug
      handler() for handler in @exitHandlers
      handlerStack.remove handlerId for handlerId in @handlers
      Mode.modes = Mode.modes.filter (mode) => mode != @
      Mode.updateBadge()
      @modeIsActive = false

  # The badge is chosen by bubbling an "updateBadge" event down the handler stack allowing each mode the
  # opportunity to choose a badge.  chooseBadge, here, is the default. It is overridden in sub-classes.
  chooseBadge: (badge) ->
    badge.badge ||= @badge

  # Shorthand for an otherwise long name.  This wraps a handler with an arbitrary return value, and always
  # yields @continueBubbling instead.  This simplifies handlers if they always continue bubbling (a common
  # case), because they do not need to be concerned with their return value (which helps keep code concise and
  # clear).
  alwaysContinueBubbling: handlerStack.alwaysContinueBubbling

  # User for sometimes suppressing badge updates.
  @badgeSuppressor: new Utils.Suppressor()

  # Static method.  Used externally and internally to initiate bubbling of an updateBadge event and to send
  # the resulting badge to the background page.  We only update the badge if this document (hence this frame)
  # has the focus.
  @updateBadge: ->
    @badgeSuppressor.unlessSuppressed ->
      if document.hasFocus()
        handlerStack.bubbleEvent "updateBadge", badge = { badge: "" }
        chrome.runtime.sendMessage
          handler: "setBadge"
          badge: badge.badge

  registerSingleton: do ->
    singletons = {} # Static.
    (key) ->
      # We're currently installing a new mode. So we'll be updating the badge shortly.  Therefore, we can
      # suppress badge updates while exiting any existing active singleton.  This prevents the badge from
      # flickering in some cases.
      if singletons[key]
        @log "singleton:", "deactivating #{singletons[key].id}" if @debug
        Mode.badgeSuppressor.runSuppresed -> singletons[key].exit()
      singletons[key] = @

      @onExit => delete singletons[key] if singletons[key] == @

  # Debugging routines.
  logStack: ->
    @log "active modes (top to bottom):"
    for mode in Mode.modes[..].reverse()
      @log " ",  mode.id

  log: (args...) ->
    console.log args...

  # Return the name of the must-recently activated mode.
  @top: ->
    @modes[@modes.length-1]?.name

# BadgeMode is a pseudo mode for triggering badge updates on focus changes and state updates. It sits at the
# bottom of the handler stack, and so it receives state changes *after* all other modes, and can override the
# badge choice of the other active modes.
# Note.  We create the the one-and-only instance here.
new class BadgeMode extends Mode
  constructor: () ->
    super
      name: "badge"
      trackState: true

    # FIXME(smblott) BadgeMode is currently triggering an updateBadge event on every focus event.  That's a
    # lot, considerably more than is necessary.  Really, it only needs to trigger when we change frame, or
    # when we change tab.
    @push
      _name: "mode-#{@id}/focus"
      "focus": => @alwaysContinueBubbling -> Mode.updateBadge()

  chooseBadge: (badge) ->
    # If we're not enabled, then post an empty badge.  BadgeMode is last, so this takes priority.
    badge.badge = "" unless @enabled

  # When the registerStateChange event bubbles to the bottom of the stack, all modes have been notified.  So
  # it's now time to update the badge.
  registerStateChange: ->
    Mode.updateBadge()

root = exports ? window
root.Mode = Mode

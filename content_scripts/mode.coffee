#
# A mode implements a number of keyboard (and possibly other) event handlers which are pushed onto the handler
# stack when the mode is activated, and popped off when it is deactivated.  The Mode class constructor takes a
# single argument "options" which can define (amongst other things):
#
# name:
#   A name for this mode.
#
# badge:
#   A badge (to appear on the browser popup).
#   Optional.  Define a badge if the badge is constant; for example, in find mode the badge is always "/".
#   Otherwise, do not define a badge, but instead override the updateBadge method; for example, in passkeys
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
# Such handlers are removed when the mode is deactivated.
#
# The following events can be handled:
#   keydown, keypress, keyup, click, focus and blur

# Debug only.
count = 0

class Mode
  # If Mode.debug is true, then we generate a trace of modes being activated and deactivated on the console.
  debug: false
  @modes: []

  # Constants; short, readable names for the return values expected by handlerStack.bubbleEvent.
  continueBubbling: true
  suppressEvent: false
  stopBubblingAndTrue: handlerStack.stopBubblingAndTrue
  stopBubblingAndFalse: handlerStack.stopBubblingAndFalse
  restartBubbling: handlerStack.restartBubbling

  constructor: (@options = {}) ->
    @handlers = []
    @exitHandlers = []
    @modeIsActive = true
    @badge = @options.badge || ""
    @name = @options.name || "anonymous"

    @count = ++count
    @id = "#{@name}-#{@count}"
    @log "activate:", @id

    @push
      keydown: @options.keydown || null
      keypress: @options.keypress || null
      keyup: @options.keyup || null
      updateBadge: (badge) => @alwaysContinueBubbling => @updateBadge badge

    # If @options.exitOnEscape is truthy, then the mode will exit when the escape key is pressed.
    if @options.exitOnEscape
      # Note. This handler ends up above the mode's own key handlers on the handler stack, so it takes
      # priority.
      @push
        _name: "mode-#{@id}/exitOnEscape"
        "keydown": (event) =>
          return @continueBubbling unless KeyboardUtils.isEscape event
          DomUtils.suppressKeyupAfterEscape handlerStack
          @exit event, event.srcElement
          @suppressEvent

    # If @options.exitOnBlur is truthy, then it should be an element.  The mode will exit when that element
    # loses the focus.
    if @options.exitOnBlur
      @push
        _name: "mode-#{@id}/exitOnBlur"
        "blur": (event) => @alwaysContinueBubbling => @exit event if event.target == @options.exitOnBlur

    # If @options.exitOnClick is truthy, then the mode will exit on any click event.
    if @options.exitOnClick
      @push
        _name: "mode-#{@id}/exitOnClick"
        "click": (event) => @alwaysContinueBubbling => @exit event

    #If @options.exitOnFocus is truthy, then the mode will exit whenever a focusable element is activated.
    if @options.exitOnFocus
      @push
        _name: "mode-#{@id}/exitOnFocus"
        "focus": (event) => @alwaysContinueBubbling =>
          @exit event if DomUtils.isFocusable event.target

    # Some modes are singletons: there may be at most one instance active at any time.  A mode is a singleton
    # if @options.singleton is truthy.  The value of @options.singleton should be the key which is intended to
    # be unique.  New instances deactivate existing instances with the same key.
    if @options.singleton
      do =>
        singletons = Mode.singletons ||= {}
        key = Utils.getIdentity @options.singleton
        @onExit -> delete singletons[key]
        @deactivateSingleton @options.singleton
        singletons[key] = @

    # If @options.trackState is truthy, then the mode mainatins the current state in @enabled and @passKeys,
    # and calls @registerStateChange() (if defined) whenever the state changes. The mode also tracks the
    # current keyQueue in @keyQueue.
    if @options.trackState
      @enabled = false
      @passKeys = ""
      @keyQueue = ""
      @push
        _name: "mode-#{@id}/registerStateChange"
        registerStateChange: ({ enabled: enabled, passKeys: passKeys }) => @alwaysContinueBubbling =>
          if enabled != @enabled or passKeys != @passKeys
            @enabled = enabled
            @passKeys = passKeys
            @registerStateChange?()
        registerKeyQueue: ({ keyQueue: keyQueue }) => @alwaysContinueBubbling => @keyQueue = keyQueue

    # If @options.passInitialKeyupEvents is set, then we pass initial non-printable keyup events to the page
    # or to other extensions (because the corresponding keydown events were passed).  This is used when
    # activating link hints, see #1522.
    if @options.passInitialKeyupEvents
      @push
        _name: "mode-#{@id}/passInitialKeyupEvents"
        keydown: => @alwaysContinueBubbling -> handlerStack.remove()
        keyup: (event) =>
          if KeyboardUtils.isPrintable event then @stopBubblingAndFalse else @stopBubblingAndTrue

    Mode.modes.push @
    Mode.updateBadge()
    @logModes()
    # End of Mode constructor.

  push: (handlers) ->
    handlers._name ||= "mode-#{@id}"
    @handlers.push handlerStack.push handlers

  unshift: (handlers) ->
    handlers._name ||= "mode-#{@id}"
    @handlers.push handlerStack.unshift handlers

  onExit: (handler) ->
    @exitHandlers.push handler

  exit: ->
    if @modeIsActive
      @log "deactivate:", @id
      handler() for handler in @exitHandlers
      handlerStack.remove handlerId for handlerId in @handlers
      Mode.modes = Mode.modes.filter (mode) => mode != @
      Mode.updateBadge()
      @modeIsActive = false

  deactivateSingleton: (singleton) ->
    Mode.singletons?[Utils.getIdentity singleton]?.exit()

  # The badge is chosen by bubbling an "updateBadge" event down the handler stack allowing each mode the
  # opportunity to choose a badge. This is overridden in sub-classes.
  updateBadge: (badge) ->
    badge.badge ||= @badge

  # Shorthand for an otherwise long name.  This wraps a handler with an arbitrary return value, and always
  # yields @continueBubbling instead.  This simplifies handlers if they always continue bubbling (a common
  # case), because they do not need to be concerned with the value they yield.
  alwaysContinueBubbling: handlerStack.alwaysContinueBubbling

  # Activate a new instance of this mode, together with all of its original options (except its main
  # keybaord-event handlers; these will be recreated).
  cloneMode: ->
    delete @options[key] for key in [ "keydown", "keypress", "keyup" ]
    new @constructor @options

  # Static method.  Used externally and internally to initiate bubbling of an updateBadge event and to send
  # the resulting badge to the background page.  We only update the badge if this document (hence this frame)
  # has the focus.
  @updateBadge: ->
    if document.hasFocus()
      handlerStack.bubbleEvent "updateBadge", badge = badge: ""
      chrome.runtime.sendMessage { handler: "setBadge", badge: badge.badge }, ->

  # Debugging routines.
  logModes: ->
    if @debug
      @log "active modes (top to bottom):"
      @log " ", mode.id for mode in Mode.modes[..].reverse()

  log: (args...) ->
    console.log args... if @debug

  # For tests only.
  @top: ->
    @modes[@modes.length-1]

  # For tests only.
  @reset: ->
    mode.exit() for mode in @modes
    @modes = []

# BadgeMode is a pseudo mode for triggering badge updates on focus changes and state updates. It sits at the
# bottom of the handler stack, and so it receives state changes *after* all other modes, and can override the
# badge choice of the other modes.
class BadgeMode extends Mode
  constructor: () ->
    super
      name: "badge"
      trackState: true

    # FIXME(smblott) BadgeMode is currently triggering an updateBadge event on every focus event.  That's a
    # lot, considerably more than necessary.  Really, it only needs to trigger when we change frame, or when
    # we change tab.
    @push
      _name: "mode-#{@id}/focus"
      "focus": => @alwaysContinueBubbling -> Mode.updateBadge()

  updateBadge: (badge) ->
    # If we're not enabled, then post an empty badge.
    badge.badge = "" unless @enabled

  # When the registerStateChange event bubbles to the bottom of the stack, all modes have been notified.  So
  # it's now time to update the badge.
  registerStateChange: ->
    Mode.updateBadge()

root = exports ? window
root.Mode = Mode
root.BadgeMode = BadgeMode

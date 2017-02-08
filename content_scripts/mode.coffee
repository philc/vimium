#
# A mode implements a number of keyboard (and possibly other) event handlers which are pushed onto the handler
# stack when the mode is activated, and popped off when it is deactivated.  The Mode class constructor takes a
# single argument "options" which can define (amongst other things):
#
# name:
#   A name for this mode.
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
  @debug: false
  @modes: []

  # Constants; short, readable names for the return values expected by handlerStack.bubbleEvent.
  continueBubbling: handlerStack.continueBubbling
  suppressEvent: handlerStack.suppressEvent
  passEventToPage: handlerStack.passEventToPage
  suppressPropagation: handlerStack.suppressPropagation
  restartBubbling: handlerStack.restartBubbling

  alwaysContinueBubbling: handlerStack.alwaysContinueBubbling
  alwaysSuppressPropagation: handlerStack.alwaysSuppressPropagation

  constructor: (@options = {}) ->
    @handlers = []
    @exitHandlers = []
    @modeIsActive = true
    @modeIsExiting = false
    @name = @options.name || "anonymous"

    @count = ++count
    @id = "#{@name}-#{@count}"
    @log "activate:", @id

    # If options.suppressAllKeyboardEvents is truthy, then all keyboard events are suppressed.  This avoids
    # the need for modes which suppress all keyboard events 1) to provide handlers for all of those events,
    # or 2) to worry about event suppression and event-handler return values.
    if @options.suppressAllKeyboardEvents
      for type in [ "keydown", "keypress", "keyup" ]
        do (handler = @options[type]) =>
          @options[type] = (event) => @alwaysSuppressPropagation => handler? event

    @push
      keydown: @options.keydown || null
      keypress: @options.keypress || null
      keyup: @options.keyup || null
      indicator: =>
        # Update the mode indicator.  Setting @options.indicator to a string shows a mode indicator in the
        # HUD.  Setting @options.indicator to 'false' forces no mode indicator.  If @options.indicator is
        # undefined, then the request propagates to the next mode.
        # The active indicator can also be changed with @setIndicator().
        if @options.indicator?
          if @options.indicator then HUD.show @options.indicator else HUD.hide true, false
          @passEventToPage
        else @continueBubbling

    # If @options.exitOnEscape is truthy, then the mode will exit when the escape key is pressed.
    if @options.exitOnEscape
      # Note. This handler ends up above the mode's own key handlers on the handler stack, so it takes
      # priority.
      @push
        _name: "mode-#{@id}/exitOnEscape"
        "keydown": (event) =>
          return @continueBubbling unless KeyboardUtils.isEscape event
          @exit event, event.target
          DomUtils.suppressKeyupAfterEscape handlerStack

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

    # If @options.exitOnScroll is truthy, then the mode will exit on any scroll event.
    if @options.exitOnScroll
      @push
        _name: "mode-#{@id}/exitOnScroll"
        "scroll": (event) => @alwaysContinueBubbling => @exit event

    # Some modes are singletons: there may be at most one instance active at any time.  A mode is a singleton
    # if @options.singleton is set.  The value of @options.singleton should be the key which is intended to be
    # unique.  New instances deactivate existing instances with the same key.
    if @options.singleton
      singletons = Mode.singletons ||= {}
      key = @options.singleton
      @onExit -> delete singletons[key]
      singletons[key]?.exit()
      singletons[key] = this

    # If @options.passInitialKeyupEvents is set, then we pass initial non-printable keyup events to the page
    # or to other extensions (because the corresponding keydown events were passed).  This is used when
    # activating link hints, see #1522.
    if @options.passInitialKeyupEvents
      @push
        _name: "mode-#{@id}/passInitialKeyupEvents"
        keydown: => @alwaysContinueBubbling -> handlerStack.remove()
        keyup: (event) =>
          if KeyboardUtils.isPrintable event then @suppressPropagation else @passEventToPage

    # if @options.suppressTrailingKeyEvents is set, then  -- on exit -- we suppress all key events until a
    # subsquent (non-repeat) keydown or keypress.  In particular, the intention is to catch keyup events for
    # keys which we have handled, but which otherwise might trigger page actions (if the page is listening for
    # keyup events).
    if @options.suppressTrailingKeyEvents
      @onExit ->
        handler = (event) ->
          if event.repeat
            handlerStack.suppressEvent
          else
            keyEventSuppressor.exit()
            handlerStack.continueBubbling

        keyEventSuppressor = new Mode
          name: "suppress-trailing-key-events"
          keydown: handler
          keypress: handler
          keyup: -> handlerStack.suppressPropagation

    Mode.modes.push this
    @setIndicator()
    @logModes()
    # End of Mode constructor.

  setIndicator: (indicator = @options.indicator) ->
    @options.indicator = indicator
    Mode.setIndicator()

  @setIndicator: ->
    handlerStack.bubbleEvent "indicator"

  push: (handlers) ->
    handlers._name ||= "mode-#{@id}"
    @handlers.push handlerStack.push handlers

  unshift: (handlers) ->
    handlers._name ||= "mode-#{@id}"
    @handlers.push handlerStack.unshift handlers

  onExit: (handler) ->
    @exitHandlers.push handler

  exit: (args...) ->
    if @modeIsActive
      @log "deactivate:", @id
      unless @modeIsExiting
        @modeIsExiting = true
        handler args... for handler in @exitHandlers
        handlerStack.remove handlerId for handlerId in @handlers
      Mode.modes = Mode.modes.filter (mode) => mode != this
      @modeIsActive = false
      @setIndicator()

  # Debugging routines.
  logModes: ->
    if Mode.debug
      @log "active modes (top to bottom):"
      @log " ", mode.id for mode in Mode.modes[..].reverse()

  log: (args...) ->
    console.log args... if Mode.debug

  # For tests only.
  @top: ->
    @modes[@modes.length-1]

  # For tests only.
  @reset: ->
    mode.exit() for mode in @modes
    @modes = []

class SuppressAllKeyboardEvents extends Mode
  constructor: (options = {}) ->
    defaults =
      name: "suppressAllKeyboardEvents"
      suppressAllKeyboardEvents: true
    super extend defaults, options

root = exports ? window
extend root, {Mode, SuppressAllKeyboardEvents}

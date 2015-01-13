# A mode is an object which inherits from this class. The constructor takes a single argument, options, with
# the following possible keys (all optional):
#
# name:         The name of the mode.
#
# parent:       The mode that this mode should be a sub-mode of. The mode will be deactivated with its parent
#               mode, and so may be thought of as being wrapped by the parent mode. (This is used to
#               implement normal mode for inputs, which we activate after finishing a search with <ret>.)
#
# noparent:     A boolean. If this is true, then the mode should not be attached to the mode hierarchy when
#               it is created.
#
# onKeydown:    Handlers for the current mode, which will be called when keydown/keypress/keyup is called on
# onKeypress:   an instance of Mode.
# onKeyup:
#
# alwaysOn:     A boolean. If this is true, then the mode cannot be deactivated -- that is, @deactivate and
#               @activate have no effect, and @isActive always returns true. (This is used for normal mode,
#               which we shouldn't ever accidentally disable.)
#
# A mode can be instantiated with a dedicated constructor that inherits from Mode, such as
#   new NormalMode()
#
# or by calling the mode constructor directly
#   new Mode
#     name: "MODE_NAME"
#     onKeydown: (event) -> doSomething event
#     onKeypress: (event) -> doSomethingDifferent event
#
# A named mode can be accessed using the helper function Mode.getMode. For example, to get the current
# instance of normal mode,
#   Mode.getMode "NORMAL"
#
# To access a sub-mode via the Mode.getMode accessor, the parent mode should be separated from each
# successive child by a `.`:
#   Mode.getMode "PARENT_MODE.CHILD_MODE"
#
# or even
#   Mode.getMode "PARENT_1.PARENT_2.PARENT_3.CHILD"
#
# The Mode.setMode method behaves similarly, setting the mode passed as the second argument to the location
# in the hierachy refrenced by the first. For example:
#   myMode = new Mode {name: "MY_MODE", noParent: true}
#   Mode.setMode "NORMAL.CUSTOM_CHILD", myMode
#   myMode == Mode.getMode "NORMAL.CUSTOM_CHILD" # Returns true
#
# These methods are also exposed on instances of Mode, to query sub-modes in the same way.
#
# To query whether a mode is active, or to modify its active status, 3 methods are provided on every instance
# of Mode:
#
# isActive       returns the current active state of the mode
# activate       sets the mode to be active, and returns the current active state
# deactivate     sets the mode to be inactive, and returns the current active state
#
# The setters activate and deactivate return the current state to highlight the fact that a mode will not
# necessarily be activated/deactivated by calling these methods; either an error or the alwaysOn option can
# cause the active state to remain unchanged.
#
# Mode.isActive, Mode.activate and Mode.deactivate provide aliases of these, fetching the mode described by
# their first argument via Mode.getMode. For example:
#
#   if Mode.isActive "INSERT"
#     Mode.deactive "INSERT" if KeyboardUtils.isEscape event
#   else if Mode.isActive "NORMAL"
#     # Do something with normal mode
#
#
#
# An instance of mode *WILL NOT* automatically register event listeners for the keydown/keypress/keyup
# methods; these have to be explicitly called from somewhere in the code, typically in
# onKeydown/onKeyup/onKeypress in vimium_frontend.coffee.
# This behaviour is by design; to automatically add listeners could allow us to end up with listeners in the
# wrong order, causing weird and wonderful behaviours.
#

class Mode
  @handledEvent = {}
  @unhandledEvent = {}
  @suppressEvent = false

  @modes = {}

  # Gets a mode in the hierachy, with each parent mode name separated from its child by a ".".
  @getMode = (modeReference) ->
    modes = modeReference.split "."
    selectedMode = this

    for mode in modes
      continue if mode == ""
      selectedMode = selectedMode.modes[mode]
      break unless selectedMode? # If the mode isnt there, don't try to get its children, return undefined.

    selectedMode

  # Sets the passed mode at the given position in the hierachy, where each parent mode name separated from
  # its child by a ".".
  @setMode = (modeReference, mode) ->
    modes = modeReference.split "."
    modeName = modes.pop()

    parentMode = @getMode modes.join "."
    return undefined unless parentMode?
    parentMode.modes[modeName] = mode
    mode

  @isActive = (modeReference) -> @getMode(modeReference)?.isActive()
  @activate = (modeReference) -> @getMode(modeReference)?.activate()
  @deactivate = (modeReference) -> @getMode(modeReference)?.deactivate()

  active: true

  constructor: (options = {}) ->
    defaultOptions =
      parent: Mode
      onKeydown: null
      onKeypress: null
      onKeyup: null
      deactivateOnEsc: false
      alwaysOn: false
    options = extend defaultOptions, options

    @modes = {}
    @name = options.name
    @onKeydown ?= options.onKeydown
    @onKeypress ?= options.onKeypress
    @onKeyup ?= options.onKeyup
    @deactivateOnEsc = options.deactivateOnEsc
    @alwaysOn = options.alwaysOn

    if options.name? and options.noParent != true
      modeParent = options.parent ? Mode
      modeParent.modes[@name]?.destructor() # Destroy the mode we're replacing, if any.
      modeParent.modes[@name] = this

  # Do any cleanup here. This will be called when another mode of the same name has replaced this one.
  destructor: -> mode.destructor() for modeName, mode of @modes

  keydown: (event) ->
    if @deactivateOnEsc
      return @handledEvent unless @handleEsc event
    retVal = @onKeydown? event
    if retVal == Mode.suppressEvent
      DomUtils.suppressEvent event
      Mode.handledEvent
    else
      retVal or Mode.unhandledEvent
  keypress: (event) ->
    retVal = @onKeypress? event
    if retVal == Mode.suppressEvent
      DomUtils.suppressEvent event
      Mode.handledEvent
    else
      retVal or Mode.unhandledEvent
  keyup: (event) ->
    retVal = @onKeyup? event
    if retVal == Mode.suppressEvent
      DomUtils.suppressEvent event
      Mode.handledEvent
    else
      retVal or Mode.unhandledEvent

  handleEsc = (event) ->
    if KeyboardUtils.isEscape event
      @deactivate()
      DomUtils.suppressEvent event
      KeydownEvents.push event
      false
    else
      true

  getMode: Mode.getMode
  setMode: Mode.setMode

  isActive: ->
    if @alwaysOn
      true
    else
      @active

  # activate/deactivate should return the same value as a call to isActive immediately after would.
  activate: ->
    if @alwaysOn
      true
    else
      @active = true
  deactivate: ->
    if @active
      # Deactivate sub-modes too.
      mode.deactivate() for modeName, mode of @modes
      if @alwaysOn
        true
      else
        @active = false

root = exports ? window
root.Mode = Mode

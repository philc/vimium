class Mode
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
    @onKeydown = options.onKeydown
    @onKeypress = options.onKeypress
    @onKeyup = options.onKeyup
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
      return false unless @handleEsc event
    @onKeydown? event
  keypress: (event) -> @onKeypress? event
  keyup: (event) -> @onKeyup? event

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
      mode.deactivate() for modeName, mode of @modes
      if @alwaysOn
        true
      else
        @active = false

root = exports ? window
root.Mode = Mode

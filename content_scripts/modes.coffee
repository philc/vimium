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

  active: true

  constructor: (@name, options = {}, @onKeydown, @onKeypress, @onKeyup) ->
    @modes = {}
    if @name? and options.noParent != true
      modeParent = options.parent ? Mode
      modeParent.modes[@name]?.destructor() # Destroy the mode we're replacing, if any.
      modeParent.modes[@name] = this

  destructor: -> mode.destructor() for modeName, mode of @modes

  keydown: (event) -> @onKeydown? event
  keypress: (event) -> @onKeypress? event
  keyup: (event) -> @onKeyup? event

  getMode: Mode.getMode
  setMode: Mode.setMode

  isActive: -> @active

  # activate/deactivate should return the same value as a call to isActive immediately after would.
  activate: -> @active = true
  deactivate: ->
    if @active
      mode.deactivate() for modeName, mode of @modes
      @active = false

root = exports ? window
root.Mode = Mode

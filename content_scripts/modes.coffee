class Mode
  @modes = {}

  modes: {}
  active: true

  constructor: (@name, options, @onKeydown, @onKeypress, @onKeyup) ->
    if @name?
      modeParent = options?.parent ? Mode
      modeParent.modes[@name]?.deactivate() # Deactivate the mode we're replacing, if any.
      modeParent.modes[@name] = this

  isActive: -> @active

  activate: -> @active = true
  deactivate: -> @active = false

root = exports ? window
root.Mode = Mode

class Mode
  @modes = {}
  active: true

  constructor: (@name, @onKeydown, @onKeypress, @onKeyup) ->
    Mode.modes[@name] = this if @name?

  isActive: -> @active

  activate: -> @active = true
  deactivate: -> @active = false

root = exports ? window
root.Mode = Mode

class VisualMode extends Mode
  constructor: ->
    super {name: "VISUAL"}
    HUD.show "Visual mode"

  onKeydown: (event) ->
    if KeyboardUtils.isEscape event
      @deactivate()
    Mode.suppressEvent
  onKeypress: (event) -> Mode.suppressEvent
  onKeyup: (event) -> Mode.suppressEvent


  deactivate: ->
    HUD.hide()
    super()

enterVisualMode = -> new VisualMode()

root = exports ? window
root.VisualMode = VisualMode
root.enterVisualMode = enterVisualMode

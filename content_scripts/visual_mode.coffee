class VisualMode extends Mode
  constructor: ->
    super "VISUAL"
    HUD.show "Visual mode"

  keydown: (event) ->
    if KeyboardUtils.isEscape event
      @deactivate()
    false
  keypress: (event) -> false
  keyup: (event) -> false


  deactivate: ->
    HUD.hide()
    super()

enterVisualMode = -> new VisualMode()

root = exports ? window
root.VisualMode = VisualMode
root.enterVisualMode = enterVisualMode

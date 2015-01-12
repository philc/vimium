class PasskeyMode extends Mode
  constructor: -> super "PASSKEY"
  keydown: (event) -> not isPassKey KeyboardUtils.getKeyChar(event)
  keypress: (event) ->
    # Ignore modifier keys by themselves.
    if (event.keyCode > 31)
      keyChar = String.fromCharCode(event.charCode)
      not isPassKey keyChar
    else
      true

  # We never want to disable passkey mode.
  isActive: -> true
  activate: -> true
  deactivate: -> true

root = exports ? window
root.PasskeyMode = PasskeyMode

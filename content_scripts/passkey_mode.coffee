class PasskeyMode extends Mode
  passKeys: null
  constructor: (passKeys) ->
    super {name: "PASSKEY"}
    if passKeys? and passKeys != ""
      @passKeys = passKeys
    else
      @deactivate()
  keydown: (event) ->
    if @isPassKey KeyboardUtils.getKeyChar(event)
      Mode.handledEvent
    else
      Mode.unhandledEvent
  keypress: (event) ->
    # Ignore modifier keys by themselves.
    if (event.keyCode > 31)
      keyChar = String.fromCharCode(event.charCode)
      if @isPassKey keyChar
        Mode.handledEvent
      else
        Mode.unhandledEvent
    else
      Mode.unhandledEvent

  # Decide whether this keyChar should be passed to the underlying page.
  # Keystrokes are *never* considered passKeys if the keyQueue is not empty.  So, for example, if 't' is a
  # passKey, then 'gt' and '99t' will neverthless be handled by vimium.
  isPassKey: (keyChar) ->
    not keyQueue and 0 <= @passKeys.indexOf keyChar

root = exports ? window
root.PasskeyMode = PasskeyMode

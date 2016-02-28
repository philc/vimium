
class PassKeysMode extends Mode
  constructor: (@normalMode) ->
    super
      name: "passkeys"
      trackState: true # Maintain @passKeys.
      keydown: (event) => @handleKeyChar event, KeyboardUtils.getKeyChar event
      keypress: (event) => @handleKeyChar event, String.fromCharCode event.charCode
      keyup: (event) => @handleKeyChar event, KeyboardUtils.getKeyChar event

  # Keystrokes are *never* considered passKeys if the user has begun entering a command.  So, for example, if
  # 't' is a passKey, then 'gt' and '99t' are neverthless be handled by Vimium.
  handleKeyChar: (event, keyChar) ->
    return @continueBubbling if event.altKey or event.ctrlKey or event.metaKey
    return @continueBubbling unless keyChar and @normalMode.isFirstKeyChar keyChar
    return @continueBubbling unless keyChar.length == 1 and 0 <= @passKeys.indexOf keyChar
    @stopBubblingAndTrue

root = exports ? window
root.PassKeysMode = PassKeysMode

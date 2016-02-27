
class PassKeysMode extends Mode
  constructor: (@normalMode) ->
    super
      name: "passkeys"
      trackState: true # Maintain @enabled, @passKeys and @keyQueue.
      keydown: (event) => @handleKeyChar event, KeyboardUtils.getKeyChar event
      keypress: (event) => @handleKeyChar event, String.fromCharCode event.charCode
      keyup: (event) => @handleKeyChar event, KeyboardUtils.getKeyChar event

  # Keystrokes are *never* considered passKeys if the user has begin entering a command.  So, for example, if
  # 't' is a passKey, then 'gt' and '99t' will neverthless be handled by Vimium.
  handleKeyChar: (event, keyChar) ->
    return @continueBubbling if event.altKey or event.ctrlKey or event.metaKey
    return @continueBubbling unless keyChar and keyChar.length == 1
    # Test whether the user has already begun entering a command.
    return @continueBubbling unless @normalMode.isFirstKeyChar keyChar
    return @continueBubbling unless 0 <= @passKeys.indexOf keyChar
    # This is a passkey.
    @stopBubblingAndTrue

root = exports ? window
root.PassKeysMode = PassKeysMode

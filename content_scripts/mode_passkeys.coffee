
class PassKeysMode extends Mode
  constructor: ->
    super
      name: "passkeys"
      trackState: true # Maintain @enabled, @passKeys and @keyQueue.
      keydown: (event) => @handleKeyChar event, KeyboardUtils.getKeyChar event
      keypress: (event) => @handleKeyChar event, String.fromCharCode event.charCode
      keyup: (event) => @handleKeyChar event, KeyboardUtils.getKeyChar event

  # Keystrokes are *never* considered passKeys if the keyQueue is not empty.  So, for example, if 't' is a
  # passKey, then 'gt' and '99t' will neverthless be handled by Vimium.
  handleKeyChar: (event, keyChar) ->
    return @continueBubbling if event.altKey or event.ctrlKey or event.metaKey
    if keyChar and not @keyQueue and 0 <= @passKeys.indexOf keyChar
      @stopBubblingAndTrue
    else
      @continueBubbling

root = exports ? window
root.PassKeysMode = PassKeysMode

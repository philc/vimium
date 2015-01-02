
class PassKeysMode extends Mode
  keyQueue: ""
  passKeys: ""

  # Decide whether this keyChar should be passed to the underlying page.  Keystrokes are *never* considered
  # passKeys if the keyQueue is not empty.  So, for example, if 't' is a passKey, then 'gt' and '99t' will
  # neverthless be handled by vimium.
  isPassKey: (keyChar) ->
    not @keyQueue and 0 <= @passKeys.indexOf(keyChar)

  handlePassKeyEvent: (event) ->
    for keyChar in [KeyboardUtils.getKeyChar(event), String.fromCharCode(event.charCode)]
      # A key is passed through to the underlying page by returning handlerStack.passDirectlyToPage.
      return handlerStack.passDirectlyToPage if keyChar and @isPassKey keyChar
    true

  setState: (response) ->
    if response.isEnabledForUrl?
      @passKeys = (response.isEnabledForUrl and response.passKeys) or ""
    if response.keyQueue?
      @keyQueue = response.keyQueue

  constructor: ->
    super
      name: "passkeys"
      keydown: (event) => @handlePassKeyEvent event
      keypress: (event) => @handlePassKeyEvent event
      keyup: -> true # Allow event to propagate.

root = exports ? window
root.PassKeysMode = PassKeysMode

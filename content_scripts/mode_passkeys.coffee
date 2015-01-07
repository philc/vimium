
class PassKeysMode extends Mode
  constructor: ->
    super
      name: "passkeys"
      keydown: (event) => @handlePassKeyEvent event
      keypress: (event) => @handlePassKeyEvent event
      trackState: true

  # Decide whether this event should be passed to the underlying page.  Keystrokes are *never* considered
  # passKeys if the keyQueue is not empty.  So, for example, if 't' is a passKey, then 'gt' and '99t' will
  # neverthless be handled by vimium.
  handlePassKeyEvent: (event) ->
    for keyChar in [KeyboardUtils.getKeyChar(event), String.fromCharCode(event.charCode)]
      return @stopBubblingAndTrue if keyChar and not @keyQueue and 0 <= @passKeys.indexOf(keyChar)
    @continueBubbling

  configure: (request) ->
    @keyQueue = request.keyQueue if request.keyQueue?

  chooseBadge: (badge) ->
    @badge = if @passKeys and not @keyQueue then "P" else ""
    super badge

root = exports ? window
root.PassKeysMode = PassKeysMode

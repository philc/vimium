
class PassKeysMode extends Mode
  keyQueue: ""
  passKeys: ""

  # This is called to set the passKeys configuration and state with various types of request from various
  # sources, so we handle several cases here.
  # TODO(smblott) Rationalize this.
  configure: (request) ->
    if request.isEnabledForUrl?
      @passKeys = (request.isEnabledForUrl and request.passKeys) or ""
      Mode.updateBadge()
    if request.enabled?
      @passKeys = (request.enabled and request.passKeys) or ""
      Mode.updateBadge()
    if request.keyQueue?
      @keyQueue = request.keyQueue

  # Decide whether this event should be passed to the underlying page.  Keystrokes are *never* considered
  # passKeys if the keyQueue is not empty.  So, for example, if 't' is a passKey, then 'gt' and '99t' will
  # neverthless be handled by vimium.
  handlePassKeyEvent: (event) ->
    for keyChar in [KeyboardUtils.getKeyChar(event), String.fromCharCode(event.charCode)]
      return @stopBubblingAndTrue if keyChar and not @keyQueue and 0 <= @passKeys.indexOf(keyChar)
    @continueBubbling

  constructor: ->
    super
      name: "passkeys"
      keydown: (event) => @handlePassKeyEvent event
      keypress: (event) => @handlePassKeyEvent event

  chooseBadge: (badge) ->
    @badge = if @passKeys and not @keyQueue then "P" else ""
    super badge

root = exports ? window
root.PassKeysMode = PassKeysMode

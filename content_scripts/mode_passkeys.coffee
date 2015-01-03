
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
      return @stopBubblingAndTrue if keyChar and @isPassKey keyChar
    @continueBubbling

  # This is called to set the pass-keys configuration and state with various types of request from various
  # sources, so we handle several cases.
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

  constructor: ->
    super
      name: "passkeys"
      keydown: (event) => @handlePassKeyEvent event
      keypress: (event) => @handlePassKeyEvent event
      keyup: => @continueBubbling

  updateBadgeForMode: (badge) ->
    @badge = if @passKeys and not @keyQueue then "P" else ""
    super badge

root = exports ? window
root.PassKeysMode = PassKeysMode

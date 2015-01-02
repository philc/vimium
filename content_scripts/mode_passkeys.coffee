
class PassKeysMode extends Mode
  keyQueue: ""
  passKeys: ""

  # Decide whether this keyChar should be passed to the underlying page.  Keystrokes are *never* considered
  # passKeys if the keyQueue is not empty.  So, for example, if 't' is a passKey, then 'gt' and '99t' will
  # neverthless be handled by vimium.
  isPassKey: (keyChar) ->
    # FIXME(smblott).  Temporary hack: attach findMode to the window (so passKeysMode can see it).  This will be
    # fixed when find mode is rationalized or #1401 is merged.
    return false if window.findMode
    not @keyQueue and 0 <= @passKeys.indexOf(keyChar)

  handlePassKeyEvent: (event) ->
    for keyChar in [KeyboardUtils.getKeyChar(event), String.fromCharCode(event.charCode)]
      # A key is passed through to the underlying page by returning handlerStack.passDirectlyToPage.
      return handlerStack.passDirectlyToPage if keyChar and @isPassKey keyChar
    Mode.propagate

  # This is called to set the pass-keys state with various types of request from various sources, so we handle
  # all of these.
  # TODO(smblott) Rationalize this.
  setState: (request) ->
    if request.isEnabledForUrl?
      @passKeys = (request.isEnabledForUrl and request.passKeys) or ""
    if request.enabled?
      @passKeys = (request.enabled and request.passKeys) or ""
    if request.keyQueue?
      @keyQueue = request.keyQueue
    @badge = if @passKeys and not @keyQueue then "P" else ""
    Mode.updateBadge()

  constructor: ->
    super
      name: "passkeys"
      keydown: (event) => @handlePassKeyEvent event
      keypress: (event) => @handlePassKeyEvent event
      keyup: -> Mode.propagate

root = exports ? window
root.PassKeysMode = PassKeysMode


class PassKeysMode extends Mode
  constructor: ->
    super
      name: "passkeys"
      trackState: true
      keydown: (event) => @handleKeyChar KeyboardUtils.getKeyChar event
      keypress: (event) => @handleKeyChar String.fromCharCode event.charCode
      keyup: (event) => @handleKeyChar String.fromCharCode event.charCode

    @keyQueue = ""
    @push
      registerKeyQueue: ({ keyQueue: keyQueue }) => @alwaysContinueBubbling => @keyQueue = keyQueue

  # Decide whether this event should be passed to the underlying page.  Keystrokes are *never* considered
  # passKeys if the keyQueue is not empty.  So, for example, if 't' is a passKey, then 'gt' and '99t' will
  # neverthless be handled by vimium.
  handleKeyChar: (keyChar) ->
    if keyChar and not @keyQueue and 0 <= @passKeys.indexOf keyChar
      @stopBubblingAndTrue
    else
      @continueBubbling

  chooseBadge: (badge) ->
    badge.badge ||= "P" if @passKeys and not @keyQueue

root = exports ? window
root.PassKeysMode = PassKeysMode

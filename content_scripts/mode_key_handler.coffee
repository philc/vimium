
class KeyHandlerMode extends Mode
  keydownEvents: {}
  setKeyMapping: (@keyMapping) -> @reset()
  setPassKeys: (@passKeys) ->

  constructor: (options) ->
    @commandHandler = options.commandHandler ? (->)
    @setKeyMapping options.keyMapping ? {}

    super extend options,
      keydown: @onKeydown.bind this
      keypress: @onKeypress.bind this
      keyup: @onKeyup.bind this
      # We cannot track keyup events if we lose the focus.
      blur: (event) => @alwaysContinueBubbling => @keydownEvents = {} if event.target == window

  onKeydown: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
    if KeyboardUtils.isEscape event
      if @countPrefix == 0 and @keyState.length == 1
        @continueBubbling
      else
        @keydownEvents[event.keyCode] = true
        @reset()
        false # Suppress event.
    else if keyChar and @keyCharIsMapped keyChar
      @unlessKeyCharIsPassKey keyChar, =>
        @keydownEvents[event.keyCode] = true
        @handleKeyChar event, keyChar
    else if keyChar
      @continueBubbling
    else if (keyChar = KeyboardUtils.getKeyChar event) and (@keyCharIsMapped(keyChar) or @isCountKey keyChar)
      # It looks like we will be handling a subsequent keypress event, so suppress propagation of this event
      # to prevent triggering page event listeners (e.g. Google instant Search).
      @unlessKeyCharIsPassKey keyChar, =>
        @keydownEvents[event.keyCode] = true
        DomUtils.suppressPropagation event
        @stopBubblingAndTrue
    else
      @continueBubbling

  onKeypress: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
    @unlessKeyCharIsPassKey keyChar, =>
      if keyChar and @keyCharIsMapped keyChar
        @handleKeyChar event, keyChar
      else if @isCountKey keyChar
        digit = parseInt keyChar
        @reset if @keyState.length == 1 then @countPrefix * 10 + digit else digit
        false # Suppress event.
      else
        @reset()
        @continueBubbling

  onKeyup: (event) ->
    if event.keyCode of @keydownEvents
      delete @keydownEvents[event.keyCode]
      DomUtils.suppressPropagation event
      @stopBubblingAndTrue
    else
      @continueBubbling

  handleKeyChar: (event, keyChar) ->
    bgLog "Handling key #{keyChar}, mode=#{@name}."
    @advanceKeyState keyChar
    command = (@keyState.filter (entry) -> entry.command)[0]
    if command?
      count = if 0 < @countPrefix then @countPrefix else 1
      @reset()
      bgLog "Calling mode=#{@name}, command=#{command.command}, count=#{count}."
      @commandHandler {command, count}
    false # Suppress event.

  keyCharIsMapped: (keyChar) ->
    (mapping for mapping in @keyState when keyChar of mapping)[0]?

  # The next key state is the current mappings matching keyChar plus @keyMapping.
  advanceKeyState: (keyChar) ->
    newMappings = (mapping[keyChar] for mapping in @keyState when keyChar of mapping)
    @keyState = [newMappings..., @keyMapping]

  # Reset the state (as if no keys had been handled), but optionally retaining the count provided.
  reset: (@countPrefix = 0) ->
    bgLog "Clearing key queue, set count=#{@countPrefix}."
    @keyState = [@keyMapping]

  isCountKey: (keyChar) ->
    keyChar?.length == 1 and (if 0 < @countPrefix then '0' else '1') <= keyChar <= '9'

  # Keystrokes are *never* considered passKeys if the user has begun entering a command.  So, for example, if
  # 't' is a passKey, then 'gt' and '99t' are neverthless handled as regular keys.
  unlessKeyCharIsPassKey: (keyChar, nonPassKeyCallback) ->
    if @passKeys and @countPrefix == 0 and @keyState.length == 1 and
        keyChar?.length == 1 and 0 <= @passKeys.indexOf keyChar
      @stopBubblingAndTrue
    else
      nonPassKeyCallback()

root = exports ? window
root.KeyHandlerMode = KeyHandlerMode

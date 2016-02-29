
class KeyHandlerMode extends Mode
  keydownEvents: {}
  setKeyMapping: (@keyMapping) -> @reset()

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
    else if keyChar and @mappingForKeyChar keyChar
      @unlessKeyCharIsPassKey keyChar, =>
        @keydownEvents[event.keyCode] = true
        @handleKeyChar event, keyChar
    else if keyChar
      @continueBubbling
    else if (keyChar = KeyboardUtils.getKeyChar event) and (@mappingForKeyChar(keyChar) or @isCountKey keyChar)
      # We will probably be handling a subsequent keypress event, so suppress propagation of this event to
      # prevent triggering page event listeners (e.g. Google instant Search).
      @unlessKeyCharIsPassKey keyChar, =>
        @keydownEvents[event.keyCode] = true
        DomUtils.suppressPropagation event
        @stopBubblingAndTrue
    else
      @continueBubbling

  onKeypress: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
    @unlessKeyCharIsPassKey keyChar, =>
      if keyChar and @mappingForKeyChar keyChar
        @handleKeyChar event, keyChar
      else if keyChar and @isCountKey keyChar
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
    commands = @keyState.filter (entry) -> entry.command
    if 0 < commands.length
      countPrefix = if 0 < @countPrefix then @countPrefix else 1
      @reset()
      bgLog "Calling mode=#{@name}, command=#{commands[0].command}, count=#{countPrefix}."
      @commandHandler command: commands[0], count: countPrefix, event: event
    false # Suppress event.

  # This returns the first key-state entry for which keyChar is mapped. The return value is truthy if a match
  # is found and falsy otherwise.
  mappingForKeyChar: (keyChar) ->
    (mapping for mapping in @keyState when keyChar of mapping)[0]

  # This is called whenever a keyChar is matched.  We keep any existing mappings matching keyChar, and append
  # a new copy of the mode's global key mappings.
  advanceKeyState: (keyChar) ->
    newMappings = (mapping[keyChar] for mapping in @keyState when keyChar of mapping)
    @keyState = [newMappings..., @keyMapping]

  # Reset the state (as if no keys had been handled), but optionally retaining the count provided.
  reset: (@countPrefix = 0) ->
    bgLog "Clearing key queue, set count=#{@countPrefix}."
    @keyState = [@keyMapping]

  isCountKey: (keyChar) ->
    keyChar.length == 1 and (if 0 < @countPrefix then '0' else '1') <= keyChar <= '9'

  # Keystrokes are *never* considered passKeys if the user has begun entering a command.  So, for example, if
  # 't' is a passKey, then 'gt' and '99t' are neverthless handled as regular keys.
  unlessKeyCharIsPassKey: (keyChar, nonPassKeyCallback) ->
    if (@passKeys? and keyChar?.length == 1 and 0 <= @passKeys.indexOf(keyChar) and
        @countPrefix == 0 and @keyState.length == 1)
      @stopBubblingAndTrue
    else
      nonPassKeyCallback()

root = exports ? window
root.KeyHandlerMode = KeyHandlerMode

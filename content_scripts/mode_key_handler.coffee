
class KeyHandlerMode extends Mode
  countPrefix: 0
  keydownEvents: {}
  keyState: []

  constructor: (options) ->
    @commandHandler = options.commandHandler ? (->)
    @setKeyMapping options.keyMapping ? {}

    delete options[option] for option in ["commandHandler", "keyMapping"]
    super extend options,
      keydown: @onKeydown.bind this
      keypress: @onKeypress.bind this
      keyup: @onKeyup.bind this
      # We cannot track matching keydown/keyup events if we lose the focus.
      blur: (event) => @alwaysContinueBubbling => @keydownEvents = {} if event.target == window

  setKeyMapping: (@keyMapping) -> @reset()

  onKeydown: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
    if KeyboardUtils.isEscape event
      if @countPrefix == 0 and @keyState.length == 1
        @continueBubbling
      else
        @reset()
        DomUtils.suppressKeyupAfterEscape handlerStack
        false # Suppress event.
    else if keyChar and @mappingForKeyChar keyChar
      @keydownEvents[event.keyCode] = true
      @handleKeyChar event, keyChar
    else if keyChar
      @continueBubbling
    else if (keyChar = KeyboardUtils.getKeyChar event) and (@mappingForKeyChar(keyChar) or @isCountKey keyChar)
      # We did not handle the event, but we might handle a subsequent keypress.  If we will be handling that
      # event, then we suppress propagation of this keydown to prevent triggering page events.
      DomUtils.suppressPropagation event
      @keydownEvents[event.keyCode] = true
      @stopBubblingAndTrue
    else
      @continueBubbling

  onKeypress: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
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
      @commandHandler commands[0], countPrefix
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

  # This tests whether keyChar would be the very first character of a command mapping.
  isFirstKeyChar: (keyChar) ->
    @countPrefix == 0 and (@mappingForKeyChar(keyChar) == @keyMapping or @isCountKey keyChar)

root = exports ? window
root.KeyHandlerMode = KeyHandlerMode

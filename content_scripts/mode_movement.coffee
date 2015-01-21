
class Movement extends Mode
  movements:
    h: "backward character"
    l: "forward character"
    k: "backward line"
    j: "forward line"
    b: "backward word"
    e: "forward word"

  constructor: (options) ->
    @countPrefix = ""
    @alterMethod = options.alterMethod
    super options

    isNumberKey = (keyChar) ->
      keyChar.length == 1 and "0" <= keyChar <= "9"

    @push
      keydown: (event) => @alwaysContinueBubbling =>
        unless event.metaKey or event.ctrlKey or event.altKey
          keyChar = KeyboardUtils.getKeyChar event
          @countPrefix += keyChar if isNumberKey keyChar
      keyup: (event) => @alwaysContinueBubbling =>
        # FIXME(smblott).  Need to revisit these test.  They do not cover all cases correctly.
        unless event.metaKey or event.ctrlKey or event.altKey or event.keyCode == keyCodes.shiftKey
          keyChar = KeyboardUtils.getKeyChar event
          if keyChar and not isNumberKey keyChar
            @countPrefix = ""

  move: (keyChar) ->
    if @movements[keyChar]
      Utils.suppressor.suppress Movement, =>
        countPrefix = if 0 < @countPrefix.length then parseInt @countPrefix else 1
        @countPrefix = ""
        for [0...countPrefix]
          if "string" == typeof @movements[keyChar]
            window.getSelection().modify @alterMethod, @movements[keyChar].split(/\s+/)...
          else if "function" == typeof @movements[keyChar]
            @movements[keyChar]()
      Utils.suppressor.unlessSuppressed Movement, => @postMove?()

  isMoveChar: (event, keyChar) ->
    return false if event.metaKey or event.ctrlKey or event.altKey
    @movements[keyChar]

# setTimeout (-> new Movement {}), 500

root = exports ? window
root.Movement = Movement

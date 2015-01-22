
# This prevents unmapped printable characters from being passed through to underlying page.
class SuppressPrintable extends Mode
  constructor: (options) ->

    handler = (event) =>
      if KeyboardUtils.isPrintable event
        if event.type == "keydown"
          DomUtils. suppressPropagation
          @stopBubblingAndTrue
        else
          @suppressEvent
      else
        @stopBubblingAndTrue

    @suppressPrintableHandlerId = handlerStack.push
      _name: "movement/suppress-printable"
      keydown: handler
      keypress: handler
      keyup: handler

    super options
    @onExit => handlerStack.remove @suppressPrintableHandlerId

# This watches keyboard events, and maintains @countPrefix as count-prefic and other keys are pressed.
class MaintainCount extends SuppressPrintable
  constructor: (options) ->
    @countPrefix = ""
    super options

    isNumberKey = (keyChar) ->
      keyChar and keyChar.length == 1 and "0" <= keyChar <= "9"

    @push
      _name: "movement/maintain-count"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            @countPrefix = if isNumberKey keyChar then @countPrefix + keyChar else ""

  countPrefixTimes: (func) ->
    countPrefix = if 0 < @countPrefix.length then parseInt @countPrefix else 1
    @countPrefix = ""
    func() for [0...countPrefix]

# This implements movement commands with count prefixes (using MaintainCount) for visual and edit modes.
class Movement extends MaintainCount
  movements:
    h: "backward character"
    l: "forward character"
    k: "backward line"
    j: "forward line"
    b: "backward word"
    e: "forward word"

  constructor: (options) ->
    @alterMethod = options.alterMethod || "extend"
    super options

    @push
      _name: "movement"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            if @movements[keyChar]
              @countPrefixTimes =>
                if "string" == typeof @movements[keyChar]
                  window.getSelection().modify @alterMethod, @movements[keyChar].split(/\s+/)...
                else if "function" == typeof @movements[keyChar]
                  @movements[keyChar]()

root = exports ? window
root.Movement = Movement

root = exports ? window

class root.Mode
  constructor: (onKeydown, onKeypress, onKeyup, @popModeCallback) ->
    @handlerId = handlerStack.push
      keydown: onKeydown
      keypress: onKeypress
      keyup: onKeyup

  popMode: ->
    handlerStack.remove @handlerId
    @popModeCallback()

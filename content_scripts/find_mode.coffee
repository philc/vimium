class FindMode extends Mode
  constructor: ->
    super "FIND"
  keydown: (event) ->
    if KeyboardUtils.isEscape event
      handleEscapeForFindMode()
      DomUtils.suppressEvent event
      KeydownEvents.push event

    else if event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey
      handleDeleteForFindMode()
      DomUtils.suppressEvent event
      KeydownEvents.push event

    else if event.keyCode == keyCodes.enter
      handleEnterForFindMode()
      DomUtils.suppressEvent event
      KeydownEvents.push event

    else unless event.metaKey or event.ctrlKey or event.altKey
      DomUtils.suppressPropagation(event)
      KeydownEvents.push event

  keypress: (event) ->
    # Get the pressed key, unless it's a modifier key.
    keyChar = if event.keyCode > 31 then String.fromCharCode(event.charCode) else ""

    if keyChar
      handleKeyCharForFindMode keyChar
      DomUtils.suppressEvent event

root = exports ? window
root.FindMode = FindMode

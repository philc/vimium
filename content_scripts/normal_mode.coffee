keyPort = chrome.runtime.connect name: "keyDown"

class NormalModeBase extends Mode

  keydown: (event) ->
    return false if false == super event
    keyUnhandled = true
    keyChar = ""

    # handle special keys, and normal input keys with modifiers being pressed. don't handle shiftKey alone (to
    # avoid / being interpreted as ?
    if (((event.metaKey || event.ctrlKey || event.altKey) && event.keyCode > 31) || (
        # TODO(philc): some events don't have a keyidentifier. How is that possible?
        event.keyIdentifier && event.keyIdentifier.slice(0, 2) != "U+"))
      keyChar = KeyboardUtils.getKeyChar(event)
      # Again, ignore just modifiers. Maybe this should replace the keyCode>31 condition.
      if (keyChar != "")
        modifiers = []

        if (event.shiftKey)
          keyChar = keyChar.toUpperCase()
        if (event.metaKey)
          modifiers.push("m")
        if (event.ctrlKey)
          modifiers.push("c")
        if (event.altKey)
          modifiers.push("a")

        for i of modifiers
          keyChar = modifiers[i] + "-" + keyChar

        if (modifiers.length > 0 || keyChar.length > 1)
          keyChar = "<" + keyChar + ">"

    if (keyChar)
      if (currentCompletionKeys.indexOf(keyChar) != -1 or isValidFirstKey(keyChar))
        DomUtils.suppressEvent event
        KeydownEvents.push event
        keyUnhandled = false

      keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

    else if (KeyboardUtils.isEscape(event))
      keyPort.postMessage({ keyChar:"<ESC>", frameId:frameId })

    else if isPassKey KeyboardUtils.getKeyChar(event)
      return false

    else if (currentCompletionKeys.indexOf(KeyboardUtils.getKeyChar(event)) != -1 ||
             isValidFirstKey(KeyboardUtils.getKeyChar(event)))
      DomUtils.suppressPropagation(event)
      KeydownEvents.push event
      keyUnhandled = false

    keyUnhandled

  onKeypress: (event) ->
    return false if false == super event
    keyChar = ""
    keyUnhandled = true

    # Ignore modifier keys by themselves.
    if (event.keyCode > 31)
      keyChar = String.fromCharCode(event.charCode)

      # Enter insert mode when the user enables the native find interface.
      if (keyChar == "f" && KeyboardUtils.isPrimaryModifierKey(event))
        enterInsertModeWithoutShowingIndicator()
        return false

      if (keyChar)
        if (isPassKey keyChar)
          return false
        if (currentCompletionKeys.indexOf(keyChar) != -1 or isValidFirstKey(keyChar))
          DomUtils.suppressEvent(event)
          keyUnhandled = false

        keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

      keyUnhandled

class NormalMode extends NormalModeBase
  constructor: ->
    super "NORMAL"

  # We never want to disable normal mode.
  isActive: -> true
  activate: -> true
  deactivate: -> true

class NormalModeForInput extends NormalModeBase
  constructor: ->
    super "INPUT_NORMAL", {parent: Mode.getMode "INSERT"}, (event) ->
      if KeyboardUtils.isEscape event
        @deactivate()
        false
      else
        true


root = exports ? window
root.NormalMode = NormalMode
root.NormalModeForInput = NormalModeForInput

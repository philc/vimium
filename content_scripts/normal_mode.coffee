keyPort = chrome.runtime.connect name: "keyDown"

class NormalModeBase extends Mode

  keydown: (event) ->
    return false if false == super event
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

      keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

    else if (KeyboardUtils.isEscape(event))
      keyPort.postMessage({ keyChar:"<ESC>", frameId:frameId })

    else if isPassKey KeyboardUtils.getKeyChar(event)
      return undefined

    else if (currentCompletionKeys.indexOf(KeyboardUtils.getKeyChar(event)) != -1 ||
             isValidFirstKey(KeyboardUtils.getKeyChar(event)))
      DomUtils.suppressPropagation(event)
      KeydownEvents.push event

  onKeypress: (event) ->
    return false if false == super event

    keyChar = ""

    # Ignore modifier keys by themselves.
    if (event.keyCode > 31)
      keyChar = String.fromCharCode(event.charCode)

      # Enter insert mode when the user enables the native find interface.
      if (keyChar == "f" && KeyboardUtils.isPrimaryModifierKey(event))
        enterInsertModeWithoutShowingIndicator()
        return

      if (keyChar)
        if (isPassKey keyChar)
          return undefined
        if (currentCompletionKeys.indexOf(keyChar) != -1 or isValidFirstKey(keyChar))
          DomUtils.suppressEvent(event)

        keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

root = exports ? window
root.NormalModeBase = NormalModeBase

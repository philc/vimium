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

    # Added to prevent propagating this event to other listeners if it's one that'll trigger a Vimium
    # command.  The goal is to avoid the scenario where Google Instant Search uses every keydown event to
    # dump us back into the search box. As a side effect, this should also prevent overriding by other sites.
    #
    # Subject to internationalization issues since we're using keyIdentifier instead of charCode (in
    # keypress).
    #
    # TOOD(ilya): Revisit this. Not sure it's the absolute best approach.
    else if (currentCompletionKeys.indexOf(KeyboardUtils.getKeyChar(event)) != -1 ||
             isValidFirstKey(KeyboardUtils.getKeyChar(event)))
      DomUtils.suppressPropagation(event)
      KeydownEvents.push event
      keyUnhandled = false

    keyUnhandled

  keypress: (event) ->
    return false if false == super event
    keyChar = ""
    keyUnhandled = true

    # Ignore modifier keys by themselves.
    if (event.keyCode > 31)
      keyChar = String.fromCharCode(event.charCode)

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

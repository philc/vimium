keyPort = chrome.runtime.connect name: "keyDown"

class NormalModeBase extends Mode

  keydown: (event) ->
    return false if false == super event
    keyHandled = false
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
        keyHandled = true

      keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

    else if (KeyboardUtils.isEscape(event))
      keyPort.postMessage({ keyChar:"<ESC>", frameId:frameId })

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
      return Mode.handledEvent

    if keyHandled
      Mode.suppressEvent
    else
      Mode.unhandledEvent

  keypress: (event) ->
    return false if false == super event
    keyChar = ""
    keyHandled = false

    # Ignore modifier keys by themselves.
    if (event.keyCode > 31)
      keyChar = String.fromCharCode(event.charCode)

      if (keyChar)
        if (currentCompletionKeys.indexOf(keyChar) != -1 or isValidFirstKey(keyChar))
          keyHandled = true

        keyPort.postMessage({ keyChar:keyChar, frameId:frameId })

    if keyHandled
      Mode.suppressEvent
    else
      Mode.unhandledEvent

# This class implements normal mode. It should be instantiated once at document load, and left enabled.
class NormalMode extends NormalModeBase
  constructor: ->
    super {name: "NORMAL", alwaysOn: true}

# This class enables normal mode when an editable element is focused. The constructor takes no arguments, and
# should be instantiated with
#   new NormalModeForInput()
#
# This is currently used to leave the user in normal mode after they perform a find, even when the selection
# is in an editable element.
class NormalModeForInput extends NormalModeBase
  constructor: ->
    super
      name: "INPUT_NORMAL"
      parent: Mode.getMode "INSERT"
      deactivateOnEsc: true


root = exports ? window
root.NormalMode = NormalMode
root.NormalModeForInput = NormalModeForInput

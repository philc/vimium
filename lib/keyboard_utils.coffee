mapKeyRegistry = {}
# NOTE: "?" here for the tests.
Utils?.monitorChromeStorage "mapKeyRegistry", (value) => mapKeyRegistry = value

KeyboardUtils =
  keyCodes:
    { ESC: 27, backspace: 8, deleteKey: 46, enter: 13, ctrlEnter: 10, space: 32, shiftKey: 16, ctrlKey: 17, f1: 112,
    f12: 123, tab: 9, downArrow: 40, upArrow: 38 }

  keyNames:
    { 37: "left", 38: "up", 39: "right", 40: "down", 32: "space", 8: "backspace" }

  init: ->
    if (navigator.userAgent.indexOf("Mac") != -1)
      @platform = "Mac"
    else if (navigator.userAgent.indexOf("Linux") != -1)
      @platform = "Linux"
    else
      @platform = "Windows"

  getKeyChar: (event) ->
    if event.keyCode of @keyNames
      @keyNames[event.keyCode]
    # It appears that event.key is not always defined (see #2453).
    else if not event.key?
      ""
    else if event.key.length == 1
      event.key
    else if event.key.length == 2 and "F1" <= event.key <= "F9"
      event.key.toLowerCase() # F1 to F9.
    else if event.key.length == 3 and "F10" <= event.key <= "F12"
      event.key.toLowerCase() # F10 to F12.
    else
      ""

  getKeyCharString: (event) ->
    if keyChar = @getKeyChar event
      modifiers = []

      keyChar = keyChar.toUpperCase() if event.shiftKey and keyChar.length == 1
      # These must be in alphabetical order (to match the sorted modifier order in Commands.normalizeKey).
      modifiers.push "a" if event.altKey
      modifiers.push "c" if event.ctrlKey
      modifiers.push "m" if event.metaKey

      keyChar = [modifiers..., keyChar].join "-"
      keyChar = "<#{keyChar}>" if 1 < keyChar.length
      keyChar = mapKeyRegistry[keyChar] ? keyChar
      keyChar

  isEscape: (event) ->
    # <c-[> is mapped to Escape in Vim by default.
    event.keyCode == @keyCodes.ESC || @getKeyCharString(event) == "<c-[>"

  isPrintable: (event) ->
    return false if event.metaKey or event.ctrlKey or event.altKey
    keyChar =
      if event.type == "keypress"
        String.fromCharCode event.charCode
      else
        @getKeyChar event
    keyChar.length == 1

KeyboardUtils.init()

root = exports ? window
root.KeyboardUtils = KeyboardUtils
# TODO(philc): A lot of code uses this keyCodes hash... maybe we shouldn't export it as a global.
root.keyCodes = KeyboardUtils.keyCodes

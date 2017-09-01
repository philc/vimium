mapKeyRegistry = {}
# NOTE: "?" here for the tests.
Utils?.monitorChromeStorage "mapKeyRegistry", (value) => mapKeyRegistry = value

KeyboardUtils =
  # This maps event.key key names to Vimium key names.
  keyNames:
    "ArrowLeft": "left", "ArrowUp": "up", "ArrowRight": "right", "ArrowDown": "down", " ": "space", "Backspace": "backspace"

  init: ->
    if (navigator.userAgent.indexOf("Mac") != -1)
      @platform = "Mac"
    else if (navigator.userAgent.indexOf("Linux") != -1)
      @platform = "Linux"
    else
      @platform = "Windows"

  getKeyChar: (event) ->
    unless Settings.get "ignoreKeyboardLayout"
      key = event.key
    else
      key = event.code
      key = key[3..] if key[...3] == "Key"
      key = key.toLowerCase() unless event.shiftKey

    if key of @keyNames
      @keyNames[key]
    # It appears that key is not always defined (see #2453).
    else if not key?
      ""
    else if key.length == 1
      key
    else if key.length == 2 and "F1" <= key <= "F9"
      key.toLowerCase() # F1 to F9.
    else if key.length == 3 and "F10" <= key <= "F12"
      key.toLowerCase() # F10 to F12.
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
    event.key == "Escape" || @getKeyCharString(event) == "<c-[>"

  isBackspace: (event) ->
    event.key in ["Backspace", "Delete"]

  isPrintable: (event) ->
    @getKeyCharString(event)?.length == 1

KeyboardUtils.init()

root = exports ? window
root.KeyboardUtils = KeyboardUtils

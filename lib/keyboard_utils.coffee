mapKeyRegistry = {}
# NOTE: "?" here for the tests.
Utils?.monitorChromeStorage "mapKeyRegistry", (value) => mapKeyRegistry = value

KeyboardUtils =
  # This maps event.key key names to Vimium key names.
  keyNames:
    "ArrowLeft": "left", "ArrowUp": "up", "ArrowRight": "right", "ArrowDown": "down", " ": "space"

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
    else unless event.code
      key = ""
    else if event.code[...6] == "Numpad"
      # We cannot correctly emulate the numpad, so fall back to event.key; see #2626.
      key = event.key
    else
      # The logic here is from the vim-like-key-notation project (https://github.com/lydell/vim-like-key-notation).
      key = event.code
      key = key[3..] if key[...3] == "Key"
      # Translate some special keys to event.key-like strings and handle <Shift>.
      if @enUsTranslations[key]
        key = if event.shiftKey then @enUsTranslations[key][1] else @enUsTranslations[key][0]
      else if key.length == 1 and not event.shiftKey
        key = key.toLowerCase()

    # It appears that key is not always defined (see #2453).
    unless key
      ""
    else if key of @keyNames
      @keyNames[key]
    else if @isModifier event
      "" # Don't resolve modifier keys.
    else if key.length == 1
      key
    else
      key.toLowerCase()

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

  isEscape: do ->
    useVimLikeEscape = true
    Utils.monitorChromeStorage "useVimLikeEscape", (value) -> useVimLikeEscape = value

    (event) ->
      # <c-[> is mapped to Escape in Vim by default.
      event.key == "Escape" or (useVimLikeEscape and @getKeyCharString(event) == "<c-[>")

  isBackspace: (event) ->
    event.key in ["Backspace", "Delete"]

  isPrintable: (event) ->
    @getKeyCharString(event)?.length == 1

  isModifier: (event) ->
    event.key in ["Control", "Shift", "Alt", "OS", "AltGraph", "Meta"]

  enUsTranslations:
    "Backquote":     ["`", "~"]
    "Minus":         ["-", "_"]
    "Equal":         ["=", "+"]
    "Backslash":     ["\\","|"]
    "IntlBackslash": ["\\","|"]
    "BracketLeft":   ["[", "{"]
    "BracketRight":  ["]", "}"]
    "Semicolon":     [";", ":"]
    "Quote":         ["'", '"']
    "Comma":         [",", "<"]
    "Period":        [".", ">"]
    "Slash":         ["/", "?"]
    "Space":         [" ", " "]
    "Digit1":        ["1", "!"]
    "Digit2":        ["2", "@"]
    "Digit3":        ["3", "#"]
    "Digit4":        ["4", "$"]
    "Digit5":        ["5", "%"]
    "Digit6":        ["6", "^"]
    "Digit7":        ["7", "&"]
    "Digit8":        ["8", "*"]
    "Digit9":        ["9", "("]
    "Digit0":        ["0", ")"]

KeyboardUtils.init()

root = exports ? (window.root ?= {})
root.KeyboardUtils = KeyboardUtils
extend window, root unless exports?


# Note. ExitOnBlur extends extends ExitOnEscapeMode.  So exit-on-escape is handled there.
class VisualMode extends ExitOnBlur
  constructor: (element=null) ->
    numberPrefix = 0

    super element, null,
      name: "visual"
      badge: "V"

      keydown: (event) =>
        keyChar = KeyboardUtils.getKeyChar event
        if (keyChar.match(/^[0-9]$/) and not event.shiftKey) or # Number prefixes.
           (event.shiftKey and keyChar == "4") or # See #1417.
           KeyboardUtils.getKeyChar(event) in ["h", "l", "k", "j", "e", "w", "0", "y"]
          DomUtils.suppressPropagation event
          @stopBubblingAndTrue
        else
          @suppressEvent

      keypress: do ->
        extendFocusArgs =
          "h": ["backward"]
          "l": ["forward"]
          "k": ["backward", "line"]
          "j": ["forward", "line"]
          "b": ["backward", "word"]
          "w": ["forward", "word"]
          "0": ["backward", "lineboundary"]
          "$": ["forward", "lineboundary"]

        (event) =>
          keyChar = String.fromCharCode event.charCode
          keyNum = parseInt keyChar

          if not isNaN(keyNum) and (keyNum != 0 or numberPrefix != 0)
            numberPrefix = 10 * numberPrefix + keyNum
          else
            numberPrefix ||= 1 # Make sure we don't do 0 repeats.
            args = extendFocusArgs[keyChar] ? []
            command =
              if args
                "VisualCommand.extendFocus"
              else if keyChar == "y"
                "VisualCommand.yank"
            Utils.invokeCommandString command, args for i in [0...numberPrefix]
            numberPrefix = 0 # Reset.

          @suppressEvent

      keyup: (event) =>
        @suppressEvent

root = exports ? window
root.VisualMode = VisualMode

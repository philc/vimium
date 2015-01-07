
# Note. ExitOnBlur extends extends ExitOnEscapeMode.  So exit-on-escape is handled there.
class VisualMode extends ExitOnBlur
  constructor: (element=null) ->
    super element, null,
      name: "visual"
      badge: "V"

      keydown: (event) =>
        if (event.shiftKey and KeyboardUtils.getKeyChar(event) == "4") or # See #1417.
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

          if keyChar of extendFocusArgs
            VisualCommand.extendFocus (extendFocusArgs[keyChar])...
          else if keyChar == "y"
            VisualCommand.yank()

          @suppressEvent

      keyup: (event) =>
        @suppressEvent

root = exports ? window
root.VisualMode = VisualMode

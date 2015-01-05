
# Note. ConstrainedMode extends extends ExitOnEscapeMode.  So exit-on-escape is handled there.
class VisualMode extends ConstrainedMode
  constructor: (element=document.body) ->
    super element, VisualMode,
      name: "visual"
      badge: "V"

      keydown: (event) =>
        return @suppressEvent

      keypress: (event) =>
        return @suppressEvent

      keyup: (event) =>
        return @suppressEvent

root = exports ? window
root.VisualMode = VisualMode

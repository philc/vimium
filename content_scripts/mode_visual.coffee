
# Note. ConstrainedMode extends extends ExitOnEscapeMode.  So exit-on-escape is handled there.
class VisualMode extends ConstrainedMode

  constructor: (element=document.body) ->
    super element,
      name: "visual"
      badge: "V"

      keydown: (event) =>
        return Mode.suppressEvent

      keypress: (event) =>
        return Mode.suppressEvent

      keyup: (event) =>
        return Mode.suppressEvent

    Mode.updateBadge()

root = exports ? window
root.VisualMode = VisualMode

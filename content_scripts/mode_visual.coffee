
# Use new VisualMode() to enter visual mode.
# Use @exit() to leave visual mode.

class VisualMode extends Mode
  constructor: ->
    super
      name: "Visual"
      badge: "V"

      keydown: (event) =>
        return Mode.suppressEvent

      keypress: (event) =>
        return Mode.suppressEvent

      keyup: (event) =>
        return Mode.suppressEvent

root = exports ? window
root.VisualMode = VisualMode

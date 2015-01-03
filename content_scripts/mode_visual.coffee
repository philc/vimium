
class VisualMode extends Mode
  constructor: ->
    super
      name: "Visual"
      badge: "V"

      keydown: (event) =>
        if KeyboardUtils.isEscape event
          @exit()
          return Mode.suppressEvent

        return Mode.suppressEvent

      keypress: (event) =>
        return Mode.suppressEvent

      keyup: (event) =>
        return Mode.suppressEvent

    Mode.updateBadge()

root = exports ? window
root.VisualMode = VisualMode

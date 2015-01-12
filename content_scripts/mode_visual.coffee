
class VisualMode extends InsertModeBlocker
  constructor: (element=null) ->
    super
      name: "visual"
      badge: "V"
      exitOnEscape: true
      exitOnBlur: element

      keydown: (event) =>
        return @suppressEvent

      keypress: (event) =>
        return @suppressEvent

      keyup: (event) =>
        return @suppressEvent

root = exports ? window
root.VisualMode = VisualMode

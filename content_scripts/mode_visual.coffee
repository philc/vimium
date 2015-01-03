
class VisualMode extends Mode

  # Proposal...  The visual selection must stay within element.  This will become relevant if we ever get so
  # far as implementing a vim-like editing mode for text areas/content editable.
  #
  constructor: (element=document.body) ->
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

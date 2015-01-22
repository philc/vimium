
class VisualMode extends Movement
  constructor: (options = {}) ->
    defaults =
      name: "visual"
      badge: "V"
      exitOnEscape: true
      exitOnBlur: options.targetElement
      alterMethod: "extend"

      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            switch String.fromCharCode event.charCode
              when "y"
                chrome.runtime.sendMessage
                  handler: "copyToClipboard"
                  data: window.getSelection().toString()
                @exit()
                # TODO(smblott). Suppress next keyup.

    super extend defaults, options
    @debug = true

root = exports ? window
root.VisualMode = VisualMode

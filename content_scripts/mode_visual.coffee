
class VisualMode extends Movement
  constructor: (options = {}) ->
    defaults =
      name: "visual"
      badge: "V"
      exitOnEscape: true
      exitOnBlur: options.targetElement
      alterMethod: "extend"

      keydown: (event) => @handleKeyEvent event, KeyboardUtils.getKeyChar event
      keyup: (event) => @handleKeyEvent event, KeyboardUtils.getKeyChar event
      keypress: (event) =>
        keyChar = String.fromCharCode event.charCode
        @handleKeyEvent event, keyChar, => @move keyChar

    super extend defaults, options

  handleKeyEvent: (event, keyChar, func = ->) ->
    if event.metaKey or event.ctrlKey or event.altKey
      @stopBubblingAndTrue
    else if event.type == "keypress" and @isMoveChar event, keyChar
      func keyChar
      @suppressEvent
    else if @handleVisualModeKey(keyChar) or @isMoveChar event, keyChar
      DomUtils.suppressPropagation
      @stopBubblingAndTrue
    else if KeyboardUtils.isPrintable event
      @suppressEvent
    else
      @stopBubblingAndTrue

  handleVisualModeKey: (keyChar) ->
    switch keyChar
      when "y"
        chrome.runtime.sendMessage
          handler: "copyToClipboard"
          data: window.getSelection().toString()
        @exit()
        true
      else
        false

root = exports ? window
root.VisualMode = VisualMode

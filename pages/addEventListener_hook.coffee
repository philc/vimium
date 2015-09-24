_addEventListener = Element::addEventListener

EventTarget::addEventListener = (type, listener, useCapture) ->
  eventTarget = if this in [document, window] then document.documentElement else this
  if type == "click" and eventTarget instanceof Element
    unless eventTarget.hasAttribute "vimium-has-onclick-listener"
      eventTarget.setAttribute "vimium-has-onclick-listener", ""
  _addEventListener.apply this, arguments

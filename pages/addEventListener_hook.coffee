_addEventListener = Element::addEventListener

Element::addEventListener = (type, listener, useCapture) ->
  if type == "click"
    unless @hasAttribute("vimium-has-onclick-listener")
      @setAttribute("vimium-has-onclick-listener", "")
  _addEventListener.apply(this, arguments)

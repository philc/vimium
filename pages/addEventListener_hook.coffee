_addEventListener = Element::addEventListener

Element::addEventListener = (type, listener, useCapture) ->
  if type == "click"
    unless @getAttribute("vimium-has-onclick-listener")
      # Perform this asynchronously; not doing so breaks some of the facebook UI for some unclear reason
      setTimeout(=>
        @setAttribute("vimium-has-onclick-listener", "")
      , 0)
  _addEventListener.apply(this, arguments)

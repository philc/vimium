_addEventListener = Element::addEventListener

Element::addEventListener = (type, listener, useCapture) ->
  if type == "click"
    unless @getAttribute("onclick")
      # Perform this asynchronously; not doing so breaks some of the facebook UI for some unclear reason
      setTimeout(=>
        @setAttribute("onclick", "")
      , 0)
  _addEventListener.apply(this, arguments)

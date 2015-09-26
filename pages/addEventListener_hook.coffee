_addEventListener = Element::addEventListener

EventTarget::addEventListener = (type, listener, useCapture) ->
  eventTarget = if this in [document, window] then document.documentElement else this
  if type == "click" and eventTarget instanceof Element
    # TODO(mrmr1993): Instead of using an attribute, use a vimium-specific event, dispatched on the element.
    # If document.contains is false, however, we should refrain from doing this, since the event will not go
    # to window, and so we cannot capture it in the content script. In this case, we ought dispatch the event
    # when the element is added to the document. I'm not yet sure how best to do this, or if it's even
    # possible to do it without a potentially huge memory leak.
    unless eventTarget.hasAttribute "vimium-has-onclick-listener"
      eventTarget.setAttribute "vimium-has-onclick-listener", ""
  _addEventListener.apply this, arguments

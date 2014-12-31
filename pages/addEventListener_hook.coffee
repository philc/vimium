return if document.documentElement.hasAttribute("vimium-listening-for-onclick-listeners") or
          document.documentElement.hasAttribute("vimium-listening-for-onclick-listeners-slow")

_addEventListener = Element::addEventListener

Element::addEventListener = (type, listener, useCapture) ->
  if type == "click"
    unless @hasAttribute "vimium-has-onclick-listener"
      @setAttribute "vimium-has-onclick-listener", ""
  _addEventListener.apply this, arguments

if window.event?
  # Executing before any page scripts.
  document.documentElement.setAttribute "vimium-listening-for-onclick-listeners", ""
else
  # Executing before DOMContentLoaded, after page scripts.
  document.documentElement.setAttribute "vimium-listening-for-onclick-listeners-slow", ""

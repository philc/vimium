return if document.documentElement.hasAttribute("vimium-listening-for-onclick-listeners") or
          document.documentElement.hasAttribute("vimium-listening-for-onclick-listeners-slow")


_addEventListener = Element::addEventListener
_removeEventListener = Element::removeEventListener

attrKey = "vimium-has-onclick-listener"

Element::addEventListener = (type, listener, useCapture) ->
  if type == "click"
    @setAttribute attrKey, ""

  _addEventListener.apply this, arguments

Element::removeEventListener = (type, listener) ->
  if type == "click"
    @removeAttribute attrKey

  _removeEventListener.apply this, arguments


if window.event?
  # Executing before any page scripts.
  document.documentElement.setAttribute "vimium-listening-for-onclick-listeners", ""
else
  # Executing before DOMContentLoaded, after page scripts.
  document.documentElement.setAttribute "vimium-listening-for-onclick-listeners-slow", ""

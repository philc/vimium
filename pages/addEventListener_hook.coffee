return if document.documentElement.hasAttribute("vimium-listening-for-onclick-listeners") or
          document.documentElement.hasAttribute("vimium-listening-for-onclick-listeners-slow")

_addEventListener = Element::addEventListener

Element::addEventListener = (type, listener, useCapture) ->
  if type == "click"
    unless @hasAttribute "vimium-has-onclick-listener"
      skipCounter = 0
      if @hasAttribute "vimium-skip-onclick-listener"
        skipCounter = parseInt @getAttribute("vimium-skip-onclick-listener")

      if skipCounter is 0
        @setAttribute "vimium-has-onclick-listener", ""
      else
        @setAttribute "vimium-skip-onclick-listener", skipCounter - 1

  _addEventListener.apply this, arguments

if window.event?
  # Executing before any page scripts.
  document.documentElement.setAttribute "vimium-listening-for-onclick-listeners", ""
else
  # Executing before DOMContentLoaded, after page scripts.
  document.documentElement.setAttribute "vimium-listening-for-onclick-listeners-slow", ""

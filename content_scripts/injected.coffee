# The code in `injectedCode()`, below, is injected into the page's own execution context.
#
# This is based on method 2b here: http://stackoverflow.com/a/9517879, and
# @mrmr1993's #1167.

injectedCode = () ->
  # Note the presence of "click" listeners installed with `addEventListener()` (for link hints).
  _addEventListener = Element::addEventListener

  Element::addEventListener = (type, listener, useCapture) ->
    if type == "click"
      try @setAttribute "_vimium-has-onclick-listener", ""
    _addEventListener?.apply this, arguments

script = document.createElement "script"
script.textContent = "(#{injectedCode.toString()})()"
(document.head || document.documentElement).appendChild script
script.remove()


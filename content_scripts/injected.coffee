# The code in `injectedCode()`, below, is injected into the page's own execution context.
#
# This is based on method 2b here: http://stackoverflow.com/a/9517879, and
# @mrmr1993's #1167.

window.vimiumOnClickAttributeName = "_vimium-has-onclick-listener"

injectedCode = (vimiumOnClickAttributeName) ->
  # Note the presence of "click" listeners installed with `addEventListener()` (for link hints).
  _addEventListener = Element::addEventListener

  Element::addEventListener = (type, listener, useCapture) ->
    @setAttribute vimiumOnClickAttributeName, "" if type == "click"
    _addEventListener.apply this, arguments

script = document.createElement "script"
script.textContent = "(#{injectedCode.toString()})('#{vimiumOnClickAttributeName}')"
(document.head || document.documentElement).appendChild script
script.remove()


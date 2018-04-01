# NOTE(smblott) Disabled pending resolution of #2997.
return

# The code in `injectedCode()`, below, is injected into the page's own execution context.
#
# This is based on method 2b here: http://stackoverflow.com/a/9517879, and
# @mrmr1993's #1167.

injectedCode = () ->
  # Note the presence of "click" listeners installed with `addEventListener()` (for link hints).
  _addEventListener = EventTarget::addEventListener
  _toString = Function::toString
  # Note some pages may override Element (see https://github.com/gdh1995/vimium-plus/issues/11)
  EL = if typeof Element == "function" then Element else HTMLElement
  Anchor = HTMLAnchorElement

  addEventListener = (type, listener, useCapture) ->
    if type == "click" and this instanceof EL
      unless this instanceof Anchor # Just skip <a>.
        try @setAttribute "_vimium-has-onclick-listener", ""
    _addEventListener?.apply this, arguments

  newToString = () ->
    real = if this == newToString then _toString else
      if this == addEventListener then _addEventListener else
      this
    _toString.apply real, arguments

  EventTarget::addEventListener = addEventListener
  # Libraries like Angular/Zone and CKEditor check if element.addEventListener is native,
  # so here we hook it to tell outsides it is exactly native.
  # This idea is from https://github.com/angular/zone.js/pull/686,
  # and see more discussions in https://github.com/ckeditor/ckeditor5-build-classic/issues/34.
  Function::toString = newToString

script = document.createElement "script"
script.textContent = "(#{injectedCode.toString()})()"
(document.head || document.documentElement).appendChild script
script.remove()


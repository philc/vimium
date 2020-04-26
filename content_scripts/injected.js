// The code in `injectedCode()`, below, is injected into the page's own execution context.
//
// This is based on method 2b here: http://stackoverflow.com/a/9517879, and
// @mrmr1993's #1167.

const injectedCode = function() {
  // Note the presence of "click" listeners installed with `addEventListener()` (for link hints).
  const _addEventListener = EventTarget.prototype.addEventListener;
  const _toString = Function.prototype.toString;
  // Note some pages may override Element (see https://github.com/gdh1995/vimium-plus/issues/11)
  const EL = typeof Element === "function" ? Element : HTMLElement;
  const Anchor = HTMLAnchorElement;

  const addEventListener = function(type, listener, useCapture) {
    if ((type === "click") && this instanceof EL) {
      if (!(this instanceof Anchor)) { // Just skip <a>.
        try { this.setAttribute("_vimium-has-onclick-listener", ""); } catch (error) {}
      }
    }
    return (_addEventListener != null ? _addEventListener.apply(this, arguments) : undefined);
  };

  var newToString = function() {
    const real = (() => {
      if (this === newToString) { return _toString; } else {
      if (this === addEventListener) { _addEventListener; } else {}
      return this;
    }
    })();
    return _toString.apply(real, arguments);
  };

  EventTarget.prototype.addEventListener = addEventListener;
  // Libraries like Angular/Zone and CKEditor check if element.addEventListener is native,
  // so here we hook it to tell outsides it is exactly native.
  // This idea is from https://github.com/angular/zone.js/pull/686,
  // and see more discussions in https://github.com/ckeditor/ckeditor5-build-classic/issues/34.
  return Function.prototype.toString = newToString;
};


// NOTE(smblott) Disabled pending resolution of #2997.
if (false) {
  const script = document.createElement("script");
  script.textContent = `(${injectedCode.toString()})()`;
  (document.head || document.documentElement).appendChild(script);
  script.remove();
}

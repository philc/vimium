var domUtils = {
  /**
   * Runs :callback if the DOM has loaded, otherwise runs it on load
   */
  documentReady: (function() {
    var loaded = false;
    window.addEventListener("DOMContentLoaded", function() { loaded = true; });
    return function(callback) {
      if (loaded)
        callback();
      else
        window.addEventListener("DOMContentLoaded", callback);
    };
  })(),

  /*
   * Takes an array of XPath selectors, adds the necessary namespaces (currently only XHTML), and applies them
   * to the document root. The namespaceResolver in evaluateXPath should be kept in sync with the namespaces
   * here.
   */
  makeXPath: function(elementArray) {
    var xpath = [];
    for (var i in elementArray)
      xpath.push("//" + elementArray[i], "//xhtml:" + elementArray[i]);
    return xpath.join(" | ");
  },

  evaluateXPath: function(xpath, resultType) {
    function namespaceResolver(namespace) {
      return namespace == "xhtml" ? "http://www.w3.org/1999/xhtml" : null;
    }
    return document.evaluate(xpath, document.documentElement, namespaceResolver, resultType, null);
  },

  /**
   * Returns the first visible clientRect of an element if it exists. Otherwise it returns null.
   */
  getVisibleClientRect: function(element) {
    // Note: this call will be expensive if we modify the DOM in between calls.
    var clientRects = element.getClientRects();
    var clientRectsLength = clientRects.length;

    for (var i = 0; i < clientRectsLength; i++) {
      if (clientRects[i].top < -2 || clientRects[i].top >= window.innerHeight - 4 ||
          clientRects[i].left < -2 || clientRects[i].left  >= window.innerWidth - 4)
        continue;

      if (clientRects[i].width < 3 || clientRects[i].height < 3)
        continue;

      // eliminate invisible elements (see test_harnesses/visibility_test.html)
      var computedStyle = window.getComputedStyle(element, null);
      if (computedStyle.getPropertyValue('visibility') != 'visible' ||
          computedStyle.getPropertyValue('display') == 'none')
        continue;

      return clientRects[i];
    }

    for (var i = 0; i < clientRectsLength; i++) {
      // If the link has zero dimensions, it may be wrapping visible
      // but floated elements. Check for this.
      if (clientRects[i].width == 0 || clientRects[i].height == 0) {
        for (var j = 0, childrenCount = element.children.length; j < childrenCount; j++) {
          var computedStyle = window.getComputedStyle(element.children[j], null);
          // Ignore child elements which are not floated and not absolutely positioned for parent elements with zero width/height
          if (computedStyle.getPropertyValue('float') == 'none' && computedStyle.getPropertyValue('position') != 'absolute')
            continue;
          var childClientRect = this.getVisibleClientRect(element.children[j]);
          if (childClientRect === null)
            continue;
          return childClientRect;
        }
      }
    };
    return null;
  },

  /*
   * Selectable means the element has a text caret; this is not the same as "focusable".
   */
  isSelectable: function(element) {
    var selectableTypes = ["search", "text", "password"];
    return (element.nodeName.toLowerCase() == "input" && selectableTypes.indexOf(element.type) >= 0) ||
        element.nodeName.toLowerCase() == "textarea";
  },

  simulateSelect: function(element) {
    element.focus();
    // When focusing a textbox, put the selection caret at the end of the textbox's contents.
    element.setSelectionRange(element.value.length, element.value.length);
  },

  simulateClick: function(element, modifiers) {
    modifiers = modifiers || {};

    var eventSequence = [ "mouseover", "mousedown", "mouseup", "click" ];
    for (var i = 0; i < eventSequence.length; i++) {
      var event = document.createEvent("MouseEvents");
      event.initMouseEvent(eventSequence[i], true, true, window, 1, 0, 0, 0, 0, modifiers.ctrlKey, false, false,
                           modifiers.metaKey, 0, null);
      // Debugging note: Firefox will not execute the element's default action if we dispatch this click event,
      // but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
      element.dispatchEvent(event);
    }
  },

  // momentarily flash a rectangular border to give user some visual feedback
  flashRect: function(rect) {
    var flashEl = document.createElement("div");
    flashEl.id = "vimiumFlash";
    flashEl.className = "vimiumReset";
    flashEl.style.left = rect.left + window.scrollX + "px";
    flashEl.style.top = rect.top  + window.scrollY  + "px";
    flashEl.style.width = rect.width + "px";
    flashEl.style.height = rect.height + "px";
    document.body.appendChild(flashEl);
    setTimeout(function() { flashEl.parentNode.removeChild(flashEl); }, 400);
  },

};

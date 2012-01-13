var utils = {
  /*
   * Takes a dot-notation object string and call the function
   * that it points to with the correct value for 'this'.
   */
  invokeCommandString: function(str, argArray) {
    var components = str.split('.');
    var obj = window;
    for (var i = 0; i < components.length - 1; i++)
      obj = obj[components[i]];
    var func = obj[components.pop()];
    return func.apply(obj, argArray);
  },

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
      if (clientRects[i].top < 0 || clientRects[i].top >= window.innerHeight - 4 ||
          clientRects[i].left < 0 || clientRects[i].left  >= window.innerWidth - 4)
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
};

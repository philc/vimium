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
};

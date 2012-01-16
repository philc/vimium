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

  /**
   * Creates a search URL from the given :query.
   */
  createSearchUrl: function(query) {
    return "http://www.google.com/search?q=" + query;
  },

  /**
   * Tries to convert :str into a valid URL.
   * We don't bother with escaping characters, however, as Chrome will do that for us.
   */
  ensureUrl: function(str) {
    // more or less RFC compliant URL host part parsing. This should be sufficient
    // for our needs
    var urlRegex = new RegExp(
      '^(?:([^:]+)(?::([^:]+))?@)?' +   // user:password (optional)     => \1, \2
      '([^:]+|\\[[^\\]]+\\])'       +   // host name (IPv6 addresses in square brackets allowed) => \3
      '(?::(\\d+))?$'                   // port number (optional)       => \4
      );

    // these are all official ASCII TLDs that are longer than 3 characters
    // (including the inofficial .onion TLD used by TOR)
    var longTlds = [ 'arpa', 'asia', 'coop', 'info', 'jobs', 'local', 'mobi', 'museum', 'name', 'onion' ];

    // are there more?
    var specialHostNames = [ 'localhost' ];

    // trim str
    str = str.replace(/^\s+|\s+$/g, '');

    // it starts with a scheme, so it's definitely an URL
    if (/^[a-z]{3,}:\/\//.test(str))
      return str;
    var strWithScheme = 'http://' + str;

    // definitely not a valid URL; treat as search query
    if (str.indexOf(' ') >= 0)
      return utils.createSearchUrl(str);

    // assuming that this is an URL, try to parse it into its meaningful parts. If matching fails, we're
    // pretty sure that we don't have some kind of URL here.
    var match = urlRegex.exec(str.split('/')[0]);
    if (!match)
      return utils.createSearchUrl(str);
    var hostname = match[3];

    // allow known special host names
    if (specialHostNames.indexOf(hostname) >= 0)
      return strWithScheme;

    // allow IPv6 addresses (need to be wrapped in brackets, as required by RFC).  It is sufficient to check
    // for a colon here, as the regex wouldn't match colons in the host name unless it's an v6 address
    if (hostname.indexOf(':') >= 0)
      return strWithScheme;

    // at this point we have to make a decision. As a heuristic, we check if the input has dots in it. If
    // yes, and if the last part could be a TLD, treat it as an URL
    var dottedParts = hostname.split('.');
    var lastPart = dottedParts[dottedParts.length-1];
    if (dottedParts.length > 1 && (lastPart.length <= 3 || longTlds.indexOf(lastPart) >= 0))
      return strWithScheme;

    // fallback: use as search query
    return utils.createSearchUrl(str);
  },

};

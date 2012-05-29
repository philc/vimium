root = (typeof(exports) === "undefined") ? window : exports

root.utils = {
  getCurrentVersion: function() {
    // Chromium #15242 will make this XHR request to access the manifest unnecessary.
    var manifestRequest = new XMLHttpRequest();
    manifestRequest.open("GET", chrome.extension.getURL("manifest.json"), false);
    manifestRequest.send(null);
    return JSON.parse(manifestRequest.responseText).version;
  },

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

  /** Sets up prototype inheritance */
  extend: function(base, sub) {
    function surrogateCtor() { }
    surrogateCtor.prototype = base.prototype;
    sub.prototype = new surrogateCtor();
    sub.prototype.constructor = sub;
  },

  /** Creates a single DOM element from :html */
  createElementFromHtml: function(html) {
    var tmp = document.createElement("div");
    tmp.innerHTML = html;
    return tmp.firstChild;
  },

  escapeHtml: function(string) { return string.replace(/</g, "&lt;").replace(/>/g, "&gt;"); },

  /**
   * Generates a unique ID
   */
  createUniqueId: (function() {
    id = 0;
    return function() { return ++id; };
  })(),

  /**
   * Completes a partial URL (without scheme)
   */
  createFullUrl: function(partialUrl) {
    if (!/^[a-z]{3,}:\/\//.test(partialUrl))
      partialUrl = 'http://' + partialUrl;
    return partialUrl
  },

  /**
   * Tries to detect, whether :str is a valid URL.
   */
  isUrl: function(str) {
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

    // it starts with a scheme, so it's definitely an URL
    if (/^[a-z]{3,}:\/\//.test(str))
      return true;

    // spaces => definitely not a valid URL
    if (str.indexOf(' ') >= 0)
      return false;

    // assuming that this is an URL, try to parse it into its meaningful parts. If matching fails, we're
    // pretty sure that we don't have some kind of URL here.
    var match = urlRegex.exec(str.split('/')[0]);
    if (!match)
      return false;
    var hostname = match[3];

    // allow known special host names
    if (specialHostNames.indexOf(hostname) >= 0)
      return true;

    // allow IPv6 addresses (need to be wrapped in brackets, as required by RFC).  It is sufficient to check
    // for a colon here, as the regex wouldn't match colons in the host name unless it's an v6 address
    if (hostname.indexOf(':') >= 0)
      return true;

    // at this point we have to make a decision. As a heuristic, we check if the input has dots in it. If
    // yes, and if the last part could be a TLD, treat it as an URL.
    var dottedParts = hostname.split('.');
    var lastPart = dottedParts[dottedParts.length-1];
    if (dottedParts.length > 1 && ((lastPart.length >= 2 && lastPart.length <= 3)
                                   || longTlds.indexOf(lastPart) >= 0))
      return true;

    // also allow IPv4 addresses
    if (/^(\d{1,3}\.){3}\d{1,3}$/.test(hostname))
      return true;

    // fallback: no URL
    return false
  },

  /**
   * Creates a search URL from the given :query.
   */
  createSearchUrl: function(query) {
    // we need to escape explictely to encode characters like "+" correctly
    return "http://www.google.com/search?q=" + encodeURIComponent(query);
  },

  /**
   * Tries to convert :str into a valid URL.
   * We don't bother with escaping characters, however, as Chrome will do that for us.
   */
  ensureUrl: function(str) {
    // trim str
    str = str.replace(/^\s+|\s+$/g, '');
    if (utils.isUrl(str))
      return utils.createFullUrl(str);
    else
      return utils.createSearchUrl(str);
  }
};

/* Execute a function with the given value for "this". Equivalent to jQuery.proxy(). */
Function.prototype.proxy = function(self) {
  var fn = this;
  return function() { return fn.apply(self, arguments); };
};

/*
 * This creates a new function out of an existing function, where the new function takes fewer arguments.
 * This allows us to pass around functions instead of functions + a partial list of arguments.
 */
Function.prototype.curry = function() {
  var fixedArguments = Array.copy(arguments);
  var fn = this;
  return function() { return fn.apply(this, fixedArguments.concat(Array.copy(arguments))); };
};

Array.copy = function(array) { return Array.prototype.slice.call(array, 0); };

/*
 * A very simple method for defining a new class (constructor and methods) using a single hash.
 * No support for inheritance is included because we really shouldn't need it.
 */
Class = {
  extend: function(properties) {
    var newClass = function() { if (this.init) this.init.apply(this, arguments); };
    newClass.prototype = properties;
    newClass.constructor = newClass;
    return newClass;
  }
};
var utils = {
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

    if (str[0] === '/')
      return "file://" + str;

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

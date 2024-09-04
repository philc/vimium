const UrlUtils = {
  // A set of top-level domains, e.g. ["com"] recognized by https://www.iana.org/domains/root/db
  tlds: null,

  // Other hard-coded TLDs that we want to recognize as URLs.
  otherTlds: [
    // Multicast DNS uses 'local' to resolve hostnames to IP addresses within small networks.
    "local",
    // A pseudo-domain used by TOR browsers.
    "onion",
  ],

  async init() {
    if (this.tlds != null) return;
    // Load the tlds.txt file relative to this module. This is required for this URL
    // to be valid both when running tests, and in the browser.
    const inUnitTests = globalThis.Deno;
    const path = "./resources/tlds.txt";
    let text;
    // Deno and the browser require different URLs to resolve tlds.txt. If we change
    // url_utils.js to be imported as a module, then can both use an import path
    // that's relative to the module:
    // const tldsFileUrl = new URL("resources/tlds.txt", new URL(import.meta.url));
    if (inUnitTests) {
      text = await Deno.readTextFile(path);
    } else {
      const response = await fetch(chrome.runtime.getURL(path));
      text = await response.text();
    }
    this.tlds = new Set(text.split("\n"));
  },

  // Tries to detect if :str is a valid URL.
  async isUrl(str) {
    if (this.tlds == null) {
      await this.init();
    }

    // Must not contain spaces
    if (str.includes(" ")) return false;

    // Starts with a scheme: URL
    if (this.urlHasProtocol(str)) return true;

    // More or less RFC compliant URL host part parsing. This should be sufficient for our needs
    const urlRegex = new RegExp(
      "^(?:([^:]+)(?::([^:]+))?@)?" + // user:password (optional) => \1, \2
        "([^:]+|\\[[^\\]]+\\])" + // host name (IPv6 addresses in square brackets allowed) => \3
        "(?::(\\d+))?$", // port number (optional) => \4
    );

    const specialHostNames = ["localhost"];

    // Try to parse the URL into its meaningful parts. If matching fails we're pretty sure that we
    // don't have some kind of URL here.
    // TODO(philc): Can't we use URL() here? This code might've been written before the URL class
    // existed.
    const match = urlRegex.exec((str.split("/"))[0]);
    if (!match) return false;
    const hostName = match[3];

    // Allow known special host names
    if (specialHostNames.includes(hostName)) return true;

    // Allow IPv6 addresses (need to be wrapped in brackets as required by RFC). It is sufficient to
    // check for a colon, as the regex wouldn't match colons in the host name unless it's an v6
    // address
    if (hostName.includes(":")) return true;

    // At this point we have to make a decision. As a heuristic, we check if the input has dots in
    // it. If yes, and if the last part could be a TLD, treat it as an URL
    const dottedParts = hostName.split(".");

    if (dottedParts.length > 1) {
      const lastPart = dottedParts.pop();
      if (this.tlds.has(lastPart) || this.otherTlds.includes(lastPart)) {
        return true;
      }
    }

    // Allow IPv4 addresses
    if (/^(\d{1,3}\.){3}\d{1,3}$/.test(hostName)) return true;

    // Fallback: no URL
    return false;
  },

  // Converts string into a full URL if it's not already one. We don't escape characters as the
  // browser will do that for us.
  async convertToUrl(string) {
    string = string.trim();

    // Special-case about:[url], view-source:[url] and the like
    if (this.hasChromeProtocol(string)) {
      return string;
    } else if (this.hasJavascriptProtocol(string)) {
      return string;
    } else if (await this.isUrl(string)) {
      return this.urlHasProtocol(string) ? string : `http://${string}`;
    } else {
      const message = `convertToUrl: can't convert "${string}" into a URL. This shouldn't happen.`;
      console.error(message);
      return null;
    }
  },

  _chromePrefixes: ["about:", "view-source:", "extension:", "chrome-extension:", "data:"],
  hasChromeProtocol(url) {
    return this._chromePrefixes.some((prefix) => url.startsWith(prefix));
  },

  hasJavascriptProtocol(url) {
    return url.startsWith("javascript:");
  },

  _urlPrefix: new RegExp("^[a-z][-+.a-z0-9]{2,}://."),
  urlHasProtocol(url) {
    return this._urlPrefix.test(url);
  },

  // Create a search URL from the given :query using the provided search URL.
  createSearchUrl(query, searchUrl) {
    if (!["%s", "%S"].some((token) => searchUrl.indexOf(token) >= 0)) {
      searchUrl += "%s";
    }
    searchUrl = searchUrl.replace(/%S/g, query);

    // Map a search query to its URL encoded form. E.g. "BBC Sport" -> "BBC%20Sport".
    const parts = query.split(/\s+/);
    const encodedQuery = parts.map(encodeURIComponent).join("%20");
    return searchUrl.replace(/%s/g, encodedQuery);
  },
};

globalThis.UrlUtils = UrlUtils;

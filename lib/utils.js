// Only pass events to the handler if they are marked as trusted by the browser.
// This is kept in the global namespace for brevity and ease of use.
if (window.forTrusted == null) {
  window.forTrusted = handler => (function(event) {
    if (event && event.isTrusted) {
      return handler.apply(this, arguments);
    } else {
      return true;
    }
  });
}

// Note(gdh1995): Info in navigator is not reliable, because sometimes browsers will provide fake values.
// For example, when `privacy.resistFingerprinting` is enabled on `about:config` of Firefox.
let browserInfo = null;
if (window.browser && browser.runtime && browser.runtime.getBrowserInfo)
  browserInfo = browser.runtime.getBrowserInfo();


var Utils = {
  isFirefox: (function() {
    // We want this browser check to also cover Firefox variants, like LibreWolf. See #3773.
    const isFirefox = (typeof browser === "object" && browser.runtime.getURL("").startsWith("moz"));
    return () => isFirefox;
  })(),

  // NOTE(gdh1995): Content scripts may access this only after `registerFrameId`
  firefoxVersion: (function() {
    // NOTE(mrmr1993): This only works in the background page.
    let ffVersion = undefined;
    if (browserInfo) {
      browserInfo.then(info => {
        ffVersion = info != null ? info.version : undefined
        browserInfo = undefined
      });
    }
    return () => ffVersion || browserInfo;
  })(),

  getCurrentVersion() {
    return chrome.runtime.getManifest().version;
  },

  // Returns true whenever the current page (or the page supplied as an argument) is from the extension's
  // origin (and thus can access the extension's localStorage).
  isExtensionPage(win) {
    if (win == null) { win = window; }
    try {
      return ((win.document.location != null ? win.document.location.origin : undefined) + "/")
        === chrome.extension.getURL("");
    } catch (error) {}
  },

  // Returns true whenever the current page is the extension's background page.
  isBackgroundPage() {
    // NOTE(philc): chrome.extension.getBackgroundPage is undefined under some circumstances, but I wasn't
    // able to determine precisely which.
    return this.isBackgroundPage && chrome.extension.getBackgroundPage &&
      chrome.extension.getBackgroundPage() === window;
  },

  // Escape all special characters, so RegExp will parse the string 'as is'.
  // Taken from http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
  escapeRegexSpecialCharacters: (function() {
    const escapeRegex = /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g;
    return str => str.replace(escapeRegex, "\\$&");
  })(),

  escapeHtml(string) { return string.replace(/</g, "&lt;").replace(/>/g, "&gt;"); },

  // Generates a unique ID
  createUniqueId: (function() {
    let id = 0;
    return () => id += 1;
  })(),

  hasChromePrefix: (function() {
    const chromePrefixes = ["about:", "view-source:", "extension:", "chrome-extension:", "data:"];
    return url => chromePrefixes.some(prefix => url.startsWith(prefix));
  })(),

  hasJavascriptPrefix(url) {
    return url.startsWith("javascript:");
  },

  hasFullUrlPrefix: (function() {
    const urlPrefix = new RegExp("^[a-z][-+.a-z0-9]{2,}://.");
    return url => urlPrefix.test(url);
  })(),

  // Decode valid escape sequences in a URI.  This is intended to mimic the best-effort decoding
  // Chrome itself seems to apply when a Javascript URI is enetered into the omnibox (or clicked).
  // See https://code.google.com/p/chromium/issues/detail?id=483000, #1611 and #1636.
  decodeURIByParts(uri) {
    return uri.split(/(?=%)/).map(function(uriComponent) {
      try {
        return decodeURIComponent(uriComponent);
      } catch (error) {
        return uriComponent;
      }
    }).join("");
  },

  // Completes a partial URL (without scheme)
  createFullUrl(partialUrl) {
    if (this.hasFullUrlPrefix(partialUrl))
      return partialUrl;
    else
      return ("http://" + partialUrl);
  },

  // Tries to detect if :str is a valid URL.
  isUrl(str) {
    // Must not contain spaces
    if (str.includes(' ')) { return false; }

    // Starts with a scheme: URL
    if (this.hasFullUrlPrefix(str)) { return true; }

    // More or less RFC compliant URL host part parsing. This should be sufficient for our needs
    const urlRegex = new RegExp(
      '^(?:([^:]+)(?::([^:]+))?@)?' + // user:password (optional) => \1, \2
      '([^:]+|\\[[^\\]]+\\])'       + // host name (IPv6 addresses in square brackets allowed) => \3
      '(?::(\\d+))?$'                 // port number (optional) => \4
      );

    // Official ASCII TLDs that are longer than 3 characters + inofficial .onion TLD used by TOR
    const longTlds = ['arpa', 'asia', 'coop', 'info', 'jobs', 'local', 'mobi', 'museum', 'name', 'onion'];

    const specialHostNames = ['localhost'];

    // Try to parse the URL into its meaningful parts. If matching fails we're pretty sure that we don't have
    // some kind of URL here.
    const match = urlRegex.exec((str.split('/'))[0]);
    if (!match) { return false; }
    const hostName = match[3];

    // Allow known special host names
    if (specialHostNames.includes(hostName)) { return true; }

    // Allow IPv6 addresses (need to be wrapped in brackets as required by RFC). It is sufficient to check for
    // a colon, as the regex wouldn't match colons in the host name unless it's an v6 address
    if (hostName.includes(':')) { return true; }

    // At this point we have to make a decision. As a heuristic, we check if the input has dots in it. If yes,
    // and if the last part could be a TLD, treat it as an URL
    const dottedParts = hostName.split('.');

    if (dottedParts.length > 1) {
      const lastPart = dottedParts.pop();
      if ((2 <= lastPart.length && lastPart.length <= 3) || longTlds.includes(lastPart)) { return true; }
    }

    // Allow IPv4 addresses
    if (/^(\d{1,3}\.){3}\d{1,3}$/.test(hostName)) { return true; }

    // Fallback: no URL
    return false;
  },

  // Map a search query to its URL encoded form. The query may be either a string or an array of strings.
  // E.g. "BBC Sport" -> "BBC+Sport".
  createSearchQuery(query) {
    if (typeof(query) === "string") { query = query.split(/\s+/); }
    return query.map(encodeURIComponent).join("+");
  },

  // Create a search URL from the given :query (using either the provided search URL, or the default one).
  // It would be better to pull the default search engine from chrome itself.  However, chrome does not provide
  // an API for doing so.
  createSearchUrl(query, searchUrl) {
    if (searchUrl == null) { searchUrl = Settings.get("searchUrl"); }
    if (!['%s', '%S'].some(token => searchUrl.indexOf(token) >= 0)) { searchUrl += "%s"; }
    searchUrl = searchUrl.replace(/%S/g, query);
    return searchUrl.replace(/%s/g, this.createSearchQuery(query));
  },

  // Extract a query from url if it appears to be a URL created from the given search URL.
  // For example, map "https://www.google.ie/search?q=star+wars&foo&bar" to "star wars".
  extractQuery: (() => {
    const queryTerminator = new RegExp("[?&#/]");
    const httpProtocolRegexp = new RegExp("^https?://");
    return function(searchUrl, url) {
      let suffixTerms;
      url = url.replace(httpProtocolRegexp);
      searchUrl = searchUrl.replace(httpProtocolRegexp);
      [ searchUrl, ...suffixTerms ] = searchUrl.split("%s");
      // We require the URL to start with the search URL.
      if (!url.startsWith(searchUrl)) { return null; }
      // We require any remaining terms in the search URL to also be present in the URL.
      for (let suffix of suffixTerms) {
        if (!(0 <= url.indexOf(suffix))) { return null; }
      }
      // We use try/catch because decodeURIComponent can throw an exception.
      try {
        return url.slice(searchUrl.length).split(queryTerminator)[0].split("+").map(decodeURIComponent).join(" ");
      } catch (error) {
        return null;
      }
    };
  })(),

  // Converts :string into a Google search if it's not already a URL. We don't bother with escaping characters
  // as Chrome will do that for us.
  convertToUrl(string) {
    string = string.trim();

    // Special-case about:[url], view-source:[url] and the like
    if (Utils.hasChromePrefix(string)) {
      return string;
    } else if (Utils.hasJavascriptPrefix(string)) {
      // In Chrome versions older than 46.0.2467.2, encoded javascript URIs weren't handled correctly.
      if (Utils.haveChromeVersion("46.0.2467.2"))
        return string;
      else
        return Utils.decodeURIByParts(string);
    } else if (Utils.isUrl(string)) {
      return Utils.createFullUrl(string);
    } else {
      return Utils.createSearchUrl(string);
    }
  },

  // detects both literals and dynamically created strings
  isString(obj) { return (typeof obj === 'string') || obj instanceof String; },

  // Transform "zjkjkabz" into "abjkz".
  distinctCharacters(str) {
    const chars = str.split("");
    return Array.from(new Set(chars)).sort().join("");
  },

  // Compares two version strings (e.g. "1.1" and "1.5") and returns
  // -1 if versionA is < versionB, 0 if they're equal, and 1 if versionA is > versionB.
  compareVersions(versionA, versionB) {
    versionA = versionA.split(".");
    versionB = versionB.split(".");
    for (let i = 0, end = Math.max(versionA.length, versionB.length); i < end; i++) {
      const a = parseInt(versionA[i] || 0, 10);
      const b = parseInt(versionB[i] || 0, 10);
      if (a < b) {
        return -1;
      } else if (a > b) {
        return 1;
      }
    }
    return 0;
  },

  // True if the current Chrome version is at least the required version.
  haveChromeVersion(required) {
    // navigator.appVersion is missing in our unit tests.
    const match = navigator.appVersion?.match(/Chrom(e|ium)\/(.*?) /);
    const chromeVersion = match ? match[2] : null;
    return chromeVersion && (0 <= Utils.compareVersions(chromeVersion, required));
  },

  // Zip two (or more) arrays:
  //   - Utils.zip([ [a,b], [1,2] ]) returns [ [a,1], [b,2] ]
  //   - Length of result is `arrays[0].length`.
  //   - Adapted from: http://stackoverflow.com/questions/4856717/javascript-equivalent-of-pythons-zip-function
  zip(arrays) {
    return arrays[0].map((_, i) => arrays.map(array => array[i]));
  },

  // locale-sensitive uppercase detection
  hasUpperCase(s) { return s.toLowerCase() !== s; },

  // Does string match any of these regexps?
  matchesAnyRegexp(regexps, string) {
    for (let re of regexps) {
      if (re.test(string)) { return true; }
    }
    return false;
  },

  // Convenience wrapper for setTimeout (with the arguments around the other way).
  setTimeout(ms, func) { return setTimeout(func, ms); },

  // Like Nodejs's nextTick.
  nextTick(func) { return this.setTimeout(0, func); },

  // Make an idempotent function.
  makeIdempotent(func) {
    return function(...args) {
      let previousFunc, ref;
      const result = ([previousFunc, func] = Array.from(ref = [func, null]), ref)[0];
      if (result) {
        return result(...Array.from(args || []));
      }
    };
  },

  monitorChromeStorage(key, setter) {
    return chrome.storage.local.get(key, (obj) => {
      if (obj[key] != null) { setter(obj[key]); }
      return chrome.storage.onChanged.addListener((changes, area) => {
        if (changes[key] && (changes[key].newValue !== undefined)) {
          return setter(changes[key].newValue);
        }
      });
    });
  }
};

// This creates a new function out of an existing function, where the new function takes fewer arguments. This
// allows us to pass around functions instead of functions + a partial list of arguments.
Function.prototype.curry = function() {
  const fixedArguments = Array.copy(arguments);
  const fn = this;
  return function() { return fn.apply(this, fixedArguments.concat(Array.copy(arguments))); };
};

Array.copy = array => Array.prototype.slice.call(array, 0);

String.prototype.reverse = function() { return this.split("").reverse().join(""); };

// A simple cache. Entries used within two expiry periods are retained, otherwise they are discarded.
// At most 2 * @entries entries are retained.
class SimpleCache {
  // expiry: expiry time in milliseconds (default, one hour)
  // entries: maximum number of entries in @cache (there may be up to this many entries in @previous, too)
  constructor(expiry, entries) {
    if (expiry == null) { expiry = 60 * 60 * 1000; }
    this.expiry = expiry;
    if (entries == null) { entries = 1000; }
    this.entries = entries;
    this.cache = {};
    this.previous = {};
    this.lastRotation = new Date();
  }

  has(key) {
    this.rotate();
    return (key in this.cache) || key in this.previous;
  }

  // Set value, and return that value.  If value is null, then delete key.
  set(key, value = null) {
    this.rotate();
    delete this.previous[key];
    if (value != null) {
      return this.cache[key] = value;
    } else {
      delete this.cache[key];
      return null;
    }
  }

  get(key) {
    this.rotate();
    if (key in this.cache) {
      return this.cache[key];
    } else if (key in this.previous) {
      this.cache[key] = this.previous[key];
      delete this.previous[key];
      return this.cache[key];
    } else {
      return null;
    }
  }

  rotate(force) {
    if (force == null) { force = false; }
    Utils.nextTick(() => {
      if (force || (this.entries < Object.keys(this.cache).length) || (this.expiry < (new Date() - this.lastRotation))) {
        this.lastRotation = new Date();
        this.previous = this.cache;
        return this.cache = {};
      }
  });
  }

  clear() {
    this.rotate(true);
    return this.rotate(true);
  }
}

// This is a simple class for the common case where we want to use some data value which may be immediately
// available, or for which we may have to wait.  It implements a use-immediately-or-wait queue, and calls the
// fetch function to fetch the data asynchronously.
class AsyncDataFetcher {
  constructor(fetch) {
    this.data = null;
    this.queue = [];
    Utils.nextTick(() => {
      return fetch(data => {
        this.data = data;
        for (let callback of this.queue) { callback(this.data); }
        return this.queue = null;
      });
    });
  }

  use(callback) {
    if (this.data != null) { return callback(this.data); } else { return this.queue.push(callback); }
  }
}

// This takes a list of jobs (functions) and runs them, asynchronously.  Functions queued with @onReady() are
// run once all of the jobs have completed.
class JobRunner {
  constructor(jobs) {
    this.jobs = jobs;
    this.fetcher = new AsyncDataFetcher(callback => {
      return this.jobs.map((job) =>
        (job => {
          Utils.nextTick(() => {
            return job(() => {
              this.jobs = this.jobs.filter(j => j !== job);
              if (this.jobs.length === 0) { return callback(true); }
            });
          });
          return null;
        })(job));
    });
  }

  onReady(callback) {
    return this.fetcher.use(callback);
  }
}

Object.assign(window, {Utils, SimpleCache, AsyncDataFetcher, JobRunner});

// Only pass events to the handler if they are marked as trusted by the browser.
// This is kept in the global namespace for brevity and ease of use.
if (globalThis.forTrusted == null) {
  globalThis.forTrusted = (handler) => (function (event) {
    if (event && event.isTrusted) {
      return handler.apply(this, arguments);
    } else {
      return true;
    }
  });
}

// Firefox does not have the storage.session API as of 2023-05-20. Until it does, use storage.local.
// Firefox 115 has beta support for storage.session, but this storage is not exposed to content
// scripts unless we use `setAccessLevel`, and that API is not yet implemented in Firefox 115.
if (chrome.storage.session == null || chrome.storage.session.setAccessLevel == null) {
  chrome.storage.session = chrome.storage.local;
  // Polyfill chrome.storage.session.setAccessLevel.
  chrome.storage.session.setAccessLevel = function () {};
}

const Utils = {
  debug: false,

  debugLog() {
    if (this.debug) {
      console.log.apply(console, arguments);
    }
  },

  // The Firefox browser name and version can only be reliably accessed from the browser page using
  // browser.runtime.getBrowserInfo(). This information is passed to the frontend via the
  // initializeFrame message, which sets each of these values. These values can also be set using
  // Utils.populateBrowserInfo().
  _browserInfoLoaded: false,
  _firefoxVersion: null,
  _isFirefox: null,

  // This should only be used by content scripts. Background pages should use BgUtils.isFirefox().
  isFirefox() {
    if (!this._browserInfoLoaded) throw new Error("browserInfo has not yet loaded.");
    return this._isFirefox;
  },

  // This should only be used by content scripts. Background pages should use
  // BgUtils.firefoxVersion().
  firefoxVersion() {
    if (!this._browserInfoLoaded) throw new Error("browserInfo has not yet loaded.");
    return this._firefoxVersion;
  },

  getCurrentVersion() {
    return chrome.runtime.getManifest().version;
  },

  async populateBrowserInfo() {
    if (this.browserInfoLoaded) return;
    const result = await chrome.runtime.sendMessage({ handler: "getBrowserInfo" });
    this._isFirefox = result.isFirefox;
    this._firefoxVersion = result.firefoxVersion;
    this._browserInfoLoaded = true;
  },

  // Escape all special characters, so RegExp will parse the string 'as is'.
  // Taken from http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
  escapeRegexSpecialCharacters: (function () {
    const escapeRegex = /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g;
    return (str) => str.replace(escapeRegex, "\\$&");
  })(),

  escapeHtml(string) {
    return string.replace(/</g, "&lt;").replace(/>/g, "&gt;");
  },

  // Generates a unique ID
  createUniqueId: (function () {
    let id = 0;
    return () => id += 1;
  })(),

  // TODO(philc): Move to UrlUrls?
  hasJavascriptPrefix(url) {
    return url.startsWith("javascript:");
  },

  // Decode valid escape sequences in a URI. This is intended to mimic the best-effort decoding
  // Chrome itself seems to apply when a Javascript URI is enetered into the omnibox (or clicked).
  // See https://code.google.com/p/chromium/issues/detail?id=483000, #1611 and #1636.
  decodeURIByParts(uri) {
    return uri.split(/(?=%)/).map(function (uriComponent) {
      try {
        return decodeURIComponent(uriComponent);
      } catch {
        return uriComponent;
      }
    }).join("");
  },

  // Extract a query from url if it appears to be a URL created from the given search URL.
  // For example, map "https://www.google.ie/search?q=star+wars&foo&bar" to "star wars".
  // TODO(philc): Currently unused; delete.
  extractQuery: (() => {
    const queryTerminator = new RegExp("[?&#/]");
    const httpProtocolRegexp = new RegExp("^https?://");
    return function (searchUrl, url) {
      let suffixTerms;
      url = url.replace(httpProtocolRegexp);
      searchUrl = searchUrl.replace(httpProtocolRegexp);
      [searchUrl, ...suffixTerms] = searchUrl.split("%s");
      // We require the URL to start with the search URL.
      if (!url.startsWith(searchUrl)) return null;
      // We require any remaining terms in the search URL to also be present in the URL.
      for (const suffix of suffixTerms) {
        if (!(0 <= url.indexOf(suffix))) return null;
      }
      // We use try/catch because decodeURIComponent can throw an exception.
      try {
        return url.slice(searchUrl.length).split(queryTerminator)[0].split("+").map(
          decodeURIComponent,
        ).join(" ");
      } catch {
        return null;
      }
    };
  })(),

  // detects both literals and dynamically created strings
  // TODO(philc): There's only one caller. Inline this.
  isString(obj) {
    return (typeof obj === "string") || obj instanceof String;
  },

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

  // Zip two (or more) arrays:
  //   - Utils.zip([ [a,b], [1,2] ]) returns [ [a,1], [b,2] ]
  //   - Length of result is `arrays[0].length`.
  //   - Adapted from: http://stackoverflow.com/questions/4856717/javascript-equivalent-of-pythons-zip-function
  zip(arrays) {
    return arrays[0].map((_, i) => arrays.map((array) => array[i]));
  },

  // Returns a copy of `object`, but only with the properties in `propertyList`.
  pick(object, propertyList) {
    const result = {};
    for (const property of propertyList) {
      if (Object.prototype.hasOwnProperty.call(object, property)) {
        result[property] = object[property];
      }
    }
    return result;
  },

  // locale-sensitive uppercase detection
  hasUpperCase(s) {
    return s.toLowerCase() !== s;
  },

  // Does string match any of these regexps?
  matchesAnyRegexp(regexps, string) {
    for (const re of regexps) {
      if (re.test(string)) return true;
    }
    return false;
  },

  // Convenience wrapper for setTimeout (with the arguments around the other way).
  setTimeout(ms, func) {
    return setTimeout(func, ms);
  },

  // Like Nodejs's nextTick.
  nextTick(func) {
    return this.setTimeout(0, func);
  },

  promiseWithTimeout(promise, ms) {
    const timeoutPromise = new Promise((_resolve, reject) => {
      setTimeout(() => reject(new Error(`Promise timed out after ${ms}ms.`)), ms);
    });
    return Promise.race([promise, timeoutPromise]);
  },

  // Make an idempotent function.
  makeIdempotent(func) {
    return function (...args) {
      // TODO(philc): Clean up this transpiled code.
      let _, ref;
      const result = ([_, func] = Array.from(ref = [func, null]), ref)[0];
      if (result) {
        return result(...Array.from(args || []));
      }
    };
  },

  monitorChromeSessionStorage(key, setter) {
    return chrome.storage.session.get(key, (obj) => {
      if (obj[key] != null) setter(obj[key]);
      return chrome.storage.onChanged.addListener((changes, _area) => {
        if (changes[key] && (changes[key].newValue !== undefined)) {
          return setter(changes[key].newValue);
        }
      });
    });
  },

  // Logs a backtrace when an assertion fails, and also halts execution by throwing an error. We do
  // both, because logged objects in console.assert are easier to read from the DevTools console
  // than just the output from an error.
  assert(expression, ...messages) {
    console.assert.apply(console, [expression].concat(messages));
    if (!expression) {
      throw new Error(messages.join(" "));
    }
  },

  // This is a wrapper around chrome.runtime.onMessage.addListener.
  // As of 2023-06-26 Chrome doesn't support passing an async function argument to the addListener
  // function. If you do, the return value to the caller of chrome.runtime.sendMessage is always
  // null. To work around this, we use an anonymous async function inside the handler that we
  // pass to addListener.
  // See here for workarounds: https://stackoverflow.com/q/44056271
  // Also see MDN's page on runtime.onMessage regarding "responding with a Promise.
  // - listenerFn: this can be async, and can return a value to the message sender.
  // - requestsHandled: a list of strings indicating which request types this listener will handle.
  //   The request type is indicated by request.handler. This is required because, while most
  //   message types are handled by just one listener (in vimium_frontend.js, or
  //   background_scripts/main.js), when the current page is a background page (like the Options
  //   page, or the Help dialog), then both listeners will receive all message types, and so each
  //   message handler must be able to distinguish which message types to respond to.
  addChromeRuntimeOnMessageListener(requestsHandled, listenerFn) {
    chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
      Utils.assert(request.handler != null, "Request is missing handler", request);
      if (!requestsHandled.includes(request.handler)) {
        return false; // Signal that we will not handle this message.
      }
      (async function () {
        const result = await listenerFn(request, sender);
        sendResponse(result);
      })();
      return true; // Indicate that we will be calling sendResponse, asynchronously.
    });
  },

  // Remove comments and leading/trailing whitespace from a list of lines, and merge lines where the
  // last character on the preceding line is "\".
  parseLines(text) {
    return text.replace(/\\\n/g, "")
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => (line.length > 0) && !(Array.from('#"').includes(line[0])));
  },
};

Array.copy = (array) => Array.prototype.slice.call(array, 0);

String.prototype.reverse = function () {
  return this.split("").reverse().join("");
};

// A cache. Entries used within two expiry periods are retained, otherwise they are discarded. At
// most 2 * maxEntries are retained.
// TODO(philc): Why is this capped at 2*maxEntries rather than maxEntries?
class SimpleCache {
  // - expiry: expiry time in milliseconds (default, one hour)
  // - maxEntries: maximum number of entries in the `cache` (there may be up to this many entries in
  //   `previous`, too)
  constructor(expiry, maxEntries) {
    if (expiry == null) expiry = 60 * 60 * 1000;
    this.expiry = expiry;
    if (maxEntries == null) maxEntries = 1000;
    this.maxEntries = maxEntries;
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
    if (force == null) force = false;
    Utils.nextTick(() => {
      if (
        force || (this.maxEntries < Object.keys(this.cache).length) ||
        (this.expiry < (new Date() - this.lastRotation))
      ) {
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

// This is a simple class for the common case where we want to use some data value which may be
// immediately available, or for which we may have to wait. It implements a use-immediately-or-wait
// queue, and calls the fetch function to fetch the data asynchronously.
class AsyncDataFetcher {
  constructor(fetch) {
    this.data = null;
    this.queue = [];
    Utils.nextTick(() => {
      fetch((data) => {
        this.data = data;
        for (const callback of this.queue) callback(this.data);
        return this.queue = null;
      });
    });
  }

  use(callback) {
    if (this.data != null) return callback(this.data);
    else return this.queue.push(callback);
  }
}

// Mixin functions for enabling a class to dispatch methods.
const EventDispatcher = {
  addEventListener(eventName, listener) {
    this.events = this.events || [];
    this.events[eventName] = this.events[eventName] || [];
    this.events[eventName].push(listener);
  },

  dispatchEvent(eventName) {
    this.events = this.events || [];
    for (const listener of this.events[eventName] || []) {
      listener();
    }
  },

  removeEventListener(eventName, listener) {
    const events = this.events || {};
    const listeners = events[eventName] || [];
    if (listeners.length > 0) {
      events[eventName] = listeners.filter((l) => l != listener);
    }
  },
};

// A struct representing a search engine entry in the "searchEngine" setting.
class UserSearchEngine {
  keyword;
  url;
  description;
  constructor(o) {
    Object.seal(this);
    if (o) Object.assign(this, o);
  }
}

// Parses a user's search engine configuration from Settings, and stores the parsed results.
// TODO(philc): Should this be responsible for updating itself when Settings changes, rather than
// the callers doing so? Or, remove this class and re-parse the configuration every keystroke in
// Vomnibar, so we don't introduce another layer of caching in the code.
const UserSearchEngines = {
  keywordToEngine: {},

  parseConfig(configText) {
    const results = {};
    for (const line of Utils.parseLines(configText)) {
      const tokens = line.split(/\s+/);
      if (tokens.length < 2) continue;
      if (!tokens[0].includes(":")) continue;
      const keyword = tokens[0].split(":")[0];
      const url = tokens[1];
      const description = tokens.length > 2 ? tokens.slice(2).join(" ") : `search (${keyword})`;
      if (UrlUtils.hasFullUrlPrefix(url) || UrlUtils.hasJavascriptPrefix(url)) {
        results[keyword] = new UserSearchEngine({ keyword, url, description });
      }
    }
    return results;
  },

  set(searchEnginesConfigText) {
    this.keywordToEngine = this.parseConfig(searchEnginesConfigText);
  },
};

Object.assign(globalThis, {
  Utils,
  SimpleCache,
  AsyncDataFetcher,
  EventDispatcher,
  UserSearchEngine,
  UserSearchEngines,
});

//
// This file contains stubs for a number of browser and chrome APIs which are missing in Deno.
// The chrome.storage.sync stub does roughly what chrome.storage.sync should do, but does so synchronously.
//

let XMLHttpRequest;

window.document = {
  createElement() { return {}; },
  addEventListener() {}
};

window.XMLHttpRequest =
  (XMLHttpRequest = class XMLHttpRequest {
    open() {}
    onload() {}
    send() {}
  });

window.chrome = {
  areRunningVimiumTests: true,

  runtime: {
    getURL() {},
    getManifest() {
      return {version: "1.2.3"};
    },
    onConnect: {
      addListener() { return true; }
    },
    onMessage: {
      addListener() { return true; }
    },
    onInstalled: {
      addListener() {}
    }
  },

  extension: {
    getURL(path) { return path; },
    getBackgroundPage() { return {}; },
    getViews() { return []; }
  },

  tabs: {
    onUpdated: {
      addListener() { return true; }
    },
    onAttached: {
      addListener() { return true; }
    },
    onMoved: {
      addListener() { return true; }
    },
    onRemoved: {
      addListener() { return true; }
    },
    onActivated: {
      addListener() { return true; }
    },
    onReplaced: {
      addListener() { return true; }
    },
    query() { return true; }
  },

  webNavigation: {
    onHistoryStateUpdated: {
      addListener() {}
    },
    onReferenceFragmentUpdated: {
      addListener() {}
    },
    onCommitted: {
      addListener() {}
    }
  },

  windows: {
    onRemoved: {
      addListener() { return true; }
    },
    getAll() { return true; },
    onFocusChanged: {
      addListener() { return true; }
    }
  },

  browserAction: {
    setBadgeBackgroundColor() {}
  },

  storage: {
    // chrome.storage.local
    local: {
      get(_, callback) { if (callback) callback({}); },
      set(_, callback) { if (callback) callback({}); },
      remove(_, callback) { if (callback) callback({}); }
    },

    // chrome.storage.onChanged
    onChanged: {
      addListener(func) {
        this.func = func;
      },

      // Fake a callback from chrome.storage.sync.
      call(key, value) {
        chrome.runtime.lastError = undefined;
        const key_value = {};
        key_value[key] = { newValue: value };
        if (this.func) { return this.func(key_value,'sync'); }
      },

      callEmpty(key) {
        chrome.runtime.lastError = undefined;
        if (this.func) {
          const items = {};
          items[key] = {};
          this.func(items,'sync');
        }
      }
    },

    session: {
      MAX_SESSION_RESULTS: 25
    },

    // chrome.storage.sync
    sync: {
      store: {},

      set(items, callback) {
        let key, value;
        chrome.runtime.lastError = undefined;
        for (key of Object.keys(items)) {
          value = items[key];
          this.store[key] = value;
        }
        if (callback) { callback(); }
        // Now, generate (supposedly asynchronous) notifications for listeners.
        for (key of Object.keys(items)) {
          value = items[key];
          window.chrome.storage.onChanged.call(key,value);
        }
      },

      get(keys, callback) {
        let key;
        chrome.runtime.lastError = undefined;
        if (keys === null) {
          keys = [];
          for (key of Object.keys(this.store)) {
            const value = this.store[key];
            keys.push(key);
          }
        }
        const items = {};
        for (key of keys) {
          items[key] = this.store[key];
        }
        // Now, generate (supposedly asynchronous) callback
        if (callback) { return callback(items); }
      },

      remove(key, callback) {
        chrome.runtime.lastError = undefined;
        if (key in this.store) {
          delete this.store[key];
        }
        if (callback) { callback(); }
        // Now, generate (supposedly asynchronous) notification for listeners.
        window.chrome.storage.onChanged.callEmpty(key);
      }
    }
  }
};

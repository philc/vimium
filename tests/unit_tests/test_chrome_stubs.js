//
// This file contains stubs for a number of browser and chrome APIs which are missing in Deno.
//

let XMLHttpRequest;

window.document = {
  createElement() {
    return {};
  },
  addEventListener() {},
};

window.XMLHttpRequest = XMLHttpRequest = class XMLHttpRequest {
  open() {}
  onload() {}
  send() {}
};

// There are 3 chrome.storage.* objects with identical APIs.
// - areaName: one of "local", "sync", "session".
const createStorageAPI = (areaName) => {
  return {
    store: {},

    async set(items) {
      let key, value;
      chrome.runtime.lastError = undefined;
      for (key of Object.keys(items)) {
        value = items[key];
        this.store[key] = value;
      }
      for (key of Object.keys(items)) {
        value = items[key];
        window.chrome.storage.onChanged.call(key, value, areaName);
      }
    },

    async get(keysArg) {
      chrome.runtime.lastError = undefined;
      if (keysArg == null) {
        return globalThis.structuredClone(this.store);
      } else if (typeof keysArg == "string") {
        const result = {};
        result[keysArg] = globalThis.structuredClone(this.store[keysArg]);
        return result;
      } else {
        const result = {};
        for (key of keysArg) {
          result[key] = globalThis.structuredClone(this.store[key]);
        }
        return result;
      }
    },

    async remove(key) {
      chrome.runtime.lastError = undefined;
      if (key in this.store) {
        delete this.store[key];
      }
      window.chrome.storage.onChanged.callEmpty(key);
    },

    async clear() {
      // TODO: Consider firing the change listener if Chrome's API implementation does.
      this.store = {};
    }
  };
};

window.chrome = {
  areRunningVimiumTests: true,

  runtime: {
    getURL() {
      return "";
    },
    getManifest() {
      return { version: "1.2.3" };
    },
    onConnect: {
      addListener() {
        return true;
      },
    },
    onMessage: {
      addListener() {
        return true;
      },
    },
    onInstalled: {
      addListener() {},
    },
  },

  extension: {
    getURL(path) {
      return path;
    },
    getBackgroundPage() {
      return {};
    },
    getViews() {
      return [];
    },
  },

  tabs: {
    onUpdated: {
      addListener() {
        return true;
      },
    },
    onAttached: {
      addListener() {
        return true;
      },
    },
    onMoved: {
      addListener() {
        return true;
      },
    },
    onRemoved: {
      addListener() {
        return true;
      },
    },
    onActivated: {
      addListener() {
        return true;
      },
    },
    onReplaced: {
      addListener() {
        return true;
      },
    },
    query() {
      return true;
    },
  },

  webNavigation: {
    onHistoryStateUpdated: {
      addListener() {},
    },
    onReferenceFragmentUpdated: {
      addListener() {},
    },
    onCommitted: {
      addListener() {},
    },
  },

  windows: {
    onRemoved: {
      addListener() {
        return true;
      },
    },
    getAll() {
      return true;
    },
    onFocusChanged: {
      addListener() {
        return true;
      },
    },
  },

  browserAction: {
    setBadgeBackgroundColor() {},
  },

  sessions: {
    MAX_SESSION_RESULTS: 25,
  },

  storage: {
    onChanged: {
      addListener(func) {
        this.func = func;
      },

      // Fake a callback from chrome.storage.sync.
      call(key, value, area) {
        chrome.runtime.lastError = undefined;
        const key_value = {};
        key_value[key] = { newValue: value };
        if (this.func) return this.func(key_value, area);
      },

      callEmpty(key) {
        chrome.runtime.lastError = undefined;
        if (this.func) {
          const items = {};
          items[key] = {};
          this.func(items, "sync");
        }
      },
    },

    local: createStorageAPI("sync"),
    sync: createStorageAPI("sync"),
    session: createStorageAPI("session"),
  },
};

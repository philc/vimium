/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
//
// Mock the Chrome extension API.
//

const root = typeof exports !== 'undefined' && exports !== null ? exports : window;
root.chromeMessages = [];

document.hasFocus = () => true;

window.forTrusted = handler => handler;

const fakeManifest = {
  version: "1.51"
};

root.chrome = {
  runtime: {
    connect() {
      return {
        onMessage: {
          addListener() {}
        },
        onDisconnect: {
          addListener() {}
        },
        postMessage() {}
      };
    },
    onMessage: {
      addListener() {}
    },
    sendMessage(message) { return chromeMessages.unshift(message); },
    getManifest() { return fakeManifest; },
    getURL(url) { return `../../${url}`; }
  },
  storage: {
    local: {
      get() {},
      set() {}
    },
    sync: {
      get(_, callback) { return callback ? callback({}) : null; },
      set() {}
    },
    onChanged: {
      addListener() {}
    }
  },
  extension: {
    inIncognitoContext: false,
    getURL(url) { return chrome.runtime.getURL(url); }
  }
};

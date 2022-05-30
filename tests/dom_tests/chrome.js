//
// Mock the Chrome extension API.
//

window.chromeMessages = [];

document.hasFocus = () => true;

window.forTrusted = handler => handler;

const fakeManifest = {
  version: "1.51"
};

window.chrome = {
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

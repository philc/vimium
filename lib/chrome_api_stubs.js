//
// Mock the Chrome extension API for our tests. In Deno and Pupeteer, the Chrome extension APIs are
// not available.
//

const shouldInstallStubs = window.location.pathname.includes("dom_tests.html") ||
  // This query string is added to pages that we load in iframes from dom_tests.html, like hud.html
  window.location.search.includes("dom_tests=true");

if (shouldInstallStubs) {
  window.chromeMessages = [];

  document.hasFocus = () => true;

  window.forTrusted = (handler) => handler;

  const fakeManifest = {
    version: "1.51",
  };

  window.chrome = {
    runtime: {
      connect() {
        return {
          onMessage: {
            addListener() {},
          },
          onDisconnect: {
            addListener() {},
          },
          postMessage() {},
        };
      },
      onMessage: {
        addListener() {},
      },
      sendMessage(message) {
        return chromeMessages.unshift(message);
      },
      getManifest() {
        return fakeManifest;
      },
      getURL(url) {
        return `../../${url}`;
      },
    },
    storage: {
      local: {
        get() {},
        set() {},
      },
      sync: {
        async get(k) {
          return {};
        },
        async set() {},
      },
      onChanged: {
        addListener() {},
      },
    },
    extension: {
      inIncognitoContext: false,
      getURL(url) {
        return chrome.runtime.getURL(url);
      },
    },
  };
}

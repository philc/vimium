import "./test_helper.js";
import "../../lib/settings.js";
import "../../background_scripts/main.js";

context("Global toggle", () => {
  setup(async () => {
    await Settings.onLoaded();
    globallyDisabled = false;
    await chrome.storage.local.clear();
  });

  teardown(async () => {
    globallyDisabled = false;
    await Settings.clear();
    await chrome.storage.local.clear();
  });

  should("toggle globallyDisabled state", async () => {
    assert.isFalse(globallyDisabled);
    stub(chrome.tabs, "query", () => []);
    await toggleGloballyDisabled();
    assert.isTrue(globallyDisabled);
    await toggleGloballyDisabled();
    assert.isFalse(globallyDisabled);
  });

  should("persist state to chrome.storage.local", async () => {
    stub(chrome.tabs, "query", () => []);
    await toggleGloballyDisabled();
    const stored = await chrome.storage.local.get("globallyDisabled");
    assert.isTrue(stored.globallyDisabled);
  });

  should("update icon on all tabs when toggled", async () => {
    const iconUpdates = [];
    stub(chrome.tabs, "query", () => [{ id: 1 }, { id: 2 }]);
    stub(chrome.tabs, "sendMessage", () => Promise.resolve());
    stub(chrome.action, "setIcon", (args) => {
      iconUpdates.push(args);
      return Promise.resolve();
    });
    await toggleGloballyDisabled();
    assert.equal(2, iconUpdates.length);
    assert.equal(1, iconUpdates[0].tabId);
    assert.equal(2, iconUpdates[1].tabId);
  });

  should("send toggleGloballyDisabled message to all tabs", async () => {
    const sentMessages = [];
    stub(chrome.tabs, "query", () => [{ id: 1 }, { id: 2 }]);
    stub(chrome.tabs, "sendMessage", (tabId, message) => {
      sentMessages.push({ tabId, message });
      return Promise.resolve();
    });
    stub(chrome.action, "setIcon", () => Promise.resolve());
    await toggleGloballyDisabled();
    assert.equal(2, sentMessages.length);
    assert.equal("toggleGloballyDisabled", sentMessages[0].message.handler);
    assert.isTrue(sentMessages[0].message.disabled);
    assert.equal(1, sentMessages[0].tabId);
    assert.equal(2, sentMessages[1].tabId);
  });
});

context("initializeFrame with global toggle", () => {
  setup(async () => {
    await Settings.onLoaded();
    globallyDisabled = false;
    await chrome.storage.local.clear();
  });

  teardown(async () => {
    globallyDisabled = false;
    await Settings.clear();
    await chrome.storage.local.clear();
  });

  should("return isEnabledForUrl false when globally disabled", async () => {
    globallyDisabled = true;
    stub(chrome.action, "setIcon", () => Promise.resolve());
    const sender = { tab: { url: "http://www.example.com/", id: 1 }, frameId: 0 };
    const response = await sendRequestHandlers.initializeFrame({}, sender);
    assert.isFalse(response.isEnabledForUrl);
    assert.equal("", response.passKeys);
  });

  should("return isEnabledForUrl true when globally enabled", async () => {
    globallyDisabled = false;
    stub(chrome.action, "setIcon", () => Promise.resolve());
    const sender = { tab: { url: "http://www.example.com/", id: 1 }, frameId: 0 };
    const response = await sendRequestHandlers.initializeFrame({}, sender);
    assert.isTrue(response.isEnabledForUrl);
  });

  should("set disabled icon when globally disabled", async () => {
    globallyDisabled = true;
    let iconPath = null;
    stub(chrome.action, "setIcon", (args) => {
      iconPath = args.path;
      return Promise.resolve();
    });
    const sender = { tab: { url: "http://www.example.com/", id: 1 }, frameId: 0 };
    await sendRequestHandlers.initializeFrame({}, sender);
    assert.isTrue(iconPath["16"].includes("disabled"));
  });

  should("respect URL exclusion rules when globally enabled", async () => {
    globallyDisabled = false;
    await Settings.set("exclusionRules", [{ pattern: "http*://mail.google.com/*", passKeys: "" }]);
    stub(chrome.action, "setIcon", () => Promise.resolve());
    const sender = {
      tab: { url: "http://mail.google.com/inbox", id: 1 },
      frameId: 0,
    };
    const response = await sendRequestHandlers.initializeFrame({}, sender);
    assert.isFalse(response.isEnabledForUrl);
  });

  should("override URL exclusion when globally disabled", async () => {
    globallyDisabled = true;
    await Settings.set("exclusionRules", []);
    stub(chrome.action, "setIcon", () => Promise.resolve());
    const sender = { tab: { url: "http://www.example.com/", id: 1 }, frameId: 0 };
    const response = await sendRequestHandlers.initializeFrame({}, sender);
    assert.isFalse(response.isEnabledForUrl);
  });
});

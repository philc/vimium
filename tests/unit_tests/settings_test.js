import "./test_helper.js";
import "../../lib/settings.js";
import "../../pages/options.js";

context("settings", () => {
  setup(() => {
    stub(Utils, "isBackgroundPage", returns(true));
    stub(Utils, "isExtensionPage", returns(true));

    localStorage.clear();
    Settings.init();
    // Avoid running update hooks which include calls to outside of settings.
    Settings.postUpdateHooks = {};
  });

  should("save settings in localStorage as JSONified strings", () => {
    Settings.set('dummy', "");
    assert.equal('""', localStorage.dummy);
  });

  should("obtain defaults if no key is stored", () => {
    assert.isFalse(Settings.has('scrollStepSize'));
    assert.equal(60, Settings.get('scrollStepSize'));
  });

  should("store values", () => {
    Settings.set('scrollStepSize', 20);
    assert.equal(20, Settings.get('scrollStepSize'));
  });

  should("revert to defaults if no key is stored", () => {
    Settings.set('scrollStepSize', 20);
    Settings.clear('scrollStepSize');
    assert.equal(60, Settings.get('scrollStepSize'));
  });

  tearDown(() => {
    localStorage.clear();
  });
});

context("synced settings", () => {
  setup(() => {
    localStorage.clear();
    Settings.init();
    // Avoid running update hooks which include calls to outside of settings.
    Settings.postUpdateHooks = {};
  });

  should("propagate non-default value via synced storage listener", () => {
    Settings.set('scrollStepSize', 20);
    assert.equal(20, Settings.get('scrollStepSize'));
    Settings.propagateChangesFromChromeStorage({ scrollStepSize: { newValue: "40" } });
    assert.equal(40, Settings.get('scrollStepSize'));
  });

  should("propagate default value via synced storage listener", () => {
    Settings.set('scrollStepSize', 20);
    assert.equal(20, Settings.get('scrollStepSize'));
    Settings.propagateChangesFromChromeStorage({ scrollStepSize: { newValue: "60" } });
    assert.equal(60, Settings.get('scrollStepSize'));
  });

  should("propagate non-default values from synced storage", () => {
    chrome.storage.sync.set({ scrollStepSize: JSON.stringify(20) });
    assert.equal(20, Settings.get('scrollStepSize'));
  });

  should("propagate default values from synced storage", () => {
    Settings.set('scrollStepSize', 20);
    chrome.storage.sync.set({ scrollStepSize: JSON.stringify(60) });
    assert.equal(60, Settings.get('scrollStepSize'));
  });

  should("clear a setting from synced storage", () => {
    Settings.set('scrollStepSize', 20);
    chrome.storage.sync.remove('scrollStepSize');
    assert.equal(60, Settings.get('scrollStepSize'));
  });

  should("trigger a postUpdateHook", () => {
    const message = "Hello World";
    let receivedMessage = "";
    Settings.postUpdateHooks['scrollStepSize'] = value => receivedMessage = value;
    chrome.storage.sync.set({ scrollStepSize: JSON.stringify(message) });
    assert.equal(message, receivedMessage);
  });

  should("sync a key which is not a known setting (without crashing)", () => {
    chrome.storage.sync.set({ notASetting: JSON.stringify("notAUsefullValue") });
  });

  tearDown(() => {
    localStorage.clear();
  });
});

context("default values", () => {
  should("have a default value for every option", () => {
    for (let key of Object.keys(Options)) {
      assert.isTrue(key in Settings.defaults);
    }
  });
});

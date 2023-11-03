import "./test_helper.js";
import "../../lib/settings.js";

context("settings", () => {
  setup(async () => {
    // Prior to Vimium 2.0.0, the settings values were encoded as JSON strings.
    await chrome.storage.sync.set({ scrollStepSize: JSON.stringify(123) });
  });

  teardown(() => {
    Settings.clear();
  });

  should("Run v2.0.0 migration when loading settings", async () => {
    let storage = await chrome.storage.sync.get(null);
    assert.equal("123", storage.scrollStepSize);
    // The JSON value should've been migrated to an int when loading settings.
    await Settings.load();
    const settings = Settings.getSettings();
    assert.equal(123, settings["scrollStepSize"]);
    // When writing settings, the JSON value should be persisted back to storage.
    await Settings.set(settings);
    storage = await chrome.storage.sync.get(null);
    assert.equal(123, storage.scrollStepSize);
  });
});

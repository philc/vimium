import "./test_helper.js";
import "../../lib/settings.js";

context("settings", () => {
  context("v2.0 migration", () => {
    setup(async () => {
      // Prior to Vimium 2.0.0, the settings values were encoded as JSON strings.
      await chrome.storage.sync.set({ scrollStepSize: JSON.stringify(123) });
    });

    teardown(async () => {
      await Settings.clear();
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

  context("v2.4 migration", () => {
    setup(async () => {
      await chrome.storage.sync.set({
        settingsVersion: "2.3",
      });
    });

    teardown(async () => {
      await Settings.clear();
    });

    should("Handle about:newtab new tab URL", async () => {
      await chrome.storage.sync.set({ newTabUrl: "about:newtab" });
      await Settings.load();
      const settings = Settings.getSettings();
      assert.equal(Settings.newTabDestinations.browserNewTabPage, settings.newTabDestination);
    });

    should("Remove deprecated option", async () => {
      await chrome.storage.sync.set({ newTabUrl: "about:newtab" });
      await Settings.load();
      const settings = Settings.getSettings();
      assert.isFalse(Object.hasOwn(settings, "newTabUrl"));
    });

    should("Handle pages/blank.html new tab URL", async () => {
      await chrome.storage.sync.set({ newTabUrl: "pages/blank.html" });
      await Settings.load();
      const settings = Settings.getSettings();
      assert.equal(Settings.newTabDestinations.vimiumNewTabPage, settings.newTabDestination);
    });

    should("Handle https://example.com new tab URL", async () => {
      await chrome.storage.sync.set({ newTabUrl: "https://example.com" });
      await Settings.load();
      const settings = Settings.getSettings();
      assert.equal(Settings.newTabDestinations.customUrl, settings.newTabDestination);
      assert.equal("https://example.com", settings.newTabCustomUrl);
    });
  });
});

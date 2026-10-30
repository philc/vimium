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

    should("Handle null newTabUrl", async () => {
      // Users who never changed newTabUrl from its old default ("about:newtab") won't have it
      // stored, because Settings.pruneOutDefaultValues removes keys equal to the default. The
      // migration should still set browserNewTabPage as the destination.
      await Settings.load();
      const settings = Settings.getSettings();
      assert.equal(Settings.newTabDestinations.browserNewTabPage, settings.newTabDestination);
    });

    should("Remove deprecated option", async () => {
      await chrome.storage.sync.set({ newTabUrl: "pages/blank.html" });
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

  context("v2.4.1 migration", () => {
    setup(async () => {
      await chrome.storage.sync.set({ settingsVersion: "2.4.0" });
    });

    teardown(async () => {
      await Settings.clear();
    });

    should("Sets default/missing newTabDestination to browserNewTabPage", async () => {
      await Settings.load();
      const settings = Settings.getSettings();
      assert.equal(Settings.newTabDestinations.browserNewTabPage, settings.newTabDestination);
    });

    should("Preserve customUrl destination", async () => {
      await chrome.storage.sync.set({ newTabDestination: Settings.newTabDestinations.customUrl });
      await Settings.load();
      const settings = Settings.getSettings();
      assert.equal(Settings.newTabDestinations.customUrl, settings.newTabDestination);
    });
  });

  context("v2.4.3 migration", () => {
    const destinations = Settings.newTabDestinations;

    const loadDestination = async () => {
      await Settings.load();
      return Settings.get("newTabDestination");
    };

    teardown(async () => {
      await Settings.clear();
    });

    should("Use the browser's new tab page on a new install", async () => {
      assert.equal(destinations.browserNewTabPage, await loadDestination());
    });

    should("Preserve the Vimium new tab page for 2.4.1 and 2.4.2 users", async () => {
      for (const settingsVersion of ["2.4.1", "2.4.2"]) {
        await chrome.storage.sync.set({ settingsVersion });
        assert.equal(destinations.vimiumNewTabPage, await loadDestination());
      }
    });

    should("Preserve explicit destinations for 2.4.2 users", async () => {
      for (const dest of [destinations.browserNewTabPage, destinations.customUrl]) {
        await chrome.storage.sync.set({ settingsVersion: "2.4.2", newTabDestination: dest });
        assert.equal(dest, await loadDestination());
      }
    });

    should("Not run on settings from 2.4.3 onward", async () => {
      await chrome.storage.sync.set({ settingsVersion: "2.4.3" });
      assert.equal(destinations.browserNewTabPage, await loadDestination());
    });

    should("Keep the Vimium new tab page across saves after migrating", async () => {
      await chrome.storage.sync.set({ settingsVersion: "2.4.2" });
      await Settings.load();
      await Settings.setSettings(Settings.getSettings());
      assert.equal(destinations.vimiumNewTabPage, await loadDestination());
    });

    should("Let a migrated user switch to the browser's new tab page", async () => {
      await chrome.storage.sync.set({ settingsVersion: "2.4.2" });
      await Settings.load();
      await Settings.set("newTabDestination", destinations.browserNewTabPage);
      assert.equal(destinations.browserNewTabPage, await loadDestination());
    });
  });
});

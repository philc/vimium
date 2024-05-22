const BgUtils = {
  tabRecency: new TabRecency(),

  // We're using browser.runtime to determine the browser name and version for Firefox. That API is
  // only available on the background page. We're not using window.navigator because it's
  // unreliable. Sometimes browser vendors will provide fake values, like when
  // `privacy.resistFingerprinting` is enabled on `about:config` of Firefox.
  isFirefox() {
    // Only Firefox has a `browser` object defined.
    return globalThis.browser
      // We want this browser check to also cover Firefox variants, like LibreWolf. See #3773.
      // We could also just check browserInfo.name against Firefox and Librewolf.
      ? browser.runtime.getURL("").startsWith("moz")
      : false;
  },

  // Get a query dictionary for `chrome.tabs.query` that will only return the visible tabs.
  visibleTabs() {
    const visibleTabsQuery = {
      currentWindow: true
    };
    // Only Firefox supports hidden tabs
    if (this.isFirefox()) {
      visibleTabsQuery.hidden = false;
    }
    return visibleTabsQuery;
  },

  // Find the real tab index in a given tab array.
  tabIndex(tab, tabs) {
    // First check if the tab is where we expect it (to save processing).
    if (tabs.length > tab.index && tabs[tab.index].index === tab.index) {
      return tab.index;
    } else {
      // If it's not where we expect, find its real position.
      return tabs.findIndex(t => t.index === tab.index);
    }
  },

  async getFirefoxVersion() {
    return globalThis.browser ? (await browser.runtime.getBrowserInfo()).version : null;
  },
};

BgUtils.tabRecency.init();

Object.assign(globalThis, {
  BgUtils,
});

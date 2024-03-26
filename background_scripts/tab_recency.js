// TabRecency associates an integer with each tab id representing how recently it has been accessed.
// The order of tabs as tracked by TabRecency is used to provide a recency-based ordering in the
// tabs vomnibar.
//
// The values are persisted to chrome.storage.session so that they're not lost when the extension's
// background page is unloaded.
//
// In theory, the browser's tab.lastAccessed timestamp field should allow us to sort tabs by
// recency, but in practice it does not work across several edge cases. See the comments on #4368.
class TabRecency {
  constructor() {
    this.counter = 1;
    this.tabIdToCounter = {};
  }

  // Add listeners to chrome.tabs, and load the index from session storage.
  // If tabs are accessed before we finish loading chrome.storage.session, the in-memory stage and
  // the session state is merged.
  init() {
    chrome.tabs.onActivated.addListener((activeInfo) => this.register(activeInfo.tabId));
    chrome.tabs.onRemoved.addListener((tabId) => this.deregister(tabId));

    chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
      this.deregister(removedTabId);
      this.register(addedTabId);
    });

    chrome.windows.onFocusChanged.addListener(async (windowId) => {
      if (windowId == chrome.windows.WINDOW_ID_NONE) return;
      const tabs = await chrome.tabs.query({ windowId, active: true });
      if (tabs[0]) this.register(tabs[0].id);
    });

    this.loadFromStorage();
  }

  // Loads the index from session storage.
  async loadFromStorage() {
    const tabsPromise = chrome.tabs.query({});
    const storagePromise = chrome.storage.session.get("tabRecency");
    const [tabs, storage] = await Promise.all([tabsPromise, storagePromise]);
    if (storage.tabRecency == null) return;

    let maxCounter = 0;
    for (const counter of Object.values(storage.tabRecency)) {
      if (maxCounter < counter) maxCounter = counter;
    }
    // Tabs loaded from storage should be considered accessed less recently than any tab tracked in
    // memory, so increase all of the in-memory tabs's counters by maxCounter.
    for (const [id, counter] of Object.entries(this.tabIdToCounter)) {
      const newCounter = counter + maxCounter;
      this.tabIdToCounter[id] = newCounter;
      if (this.counter < newCounter) this.counter = newCounter;
    }

    const combined = Object.assign({}, storage.tabRecency, this.tabIdToCounter);

    // Remove any tab IDs which may be no longer present.
    const tabIds = new Set(tabs.map((t) => t.id));
    for (const id in combined) {
      if (!tabIds.has(parseInt(id))) {
        delete combined[id];
      }
    }
    this.tabIdToCounter = combined;
  }

  async saveToStorage() {
    await chrome.storage.session.set({ tabRecency: this.tabIdToCounter });
  }

  register(tabId) {
    this.counter++;
    this.tabIdToCounter[tabId] = this.counter;
    this.saveToStorage();
  }

  deregister(tabId) {
    delete this.tabIdToCounter[tabId];
    this.saveToStorage();
  }

  // Recently-visited tabs get a higher score (except the current tab, which gets a low score).
  recencyScore(tabId) {
    const tabCounter = this.tabIdToCounter[tabId];
    const isCurrentTab = tabCounter == this.counter;
    if (isCurrentTab) return 0;
    return (tabCounter ?? 1) / this.counter; // tabCounter may be null.
  }

  // Returns a list of tab Ids sorted by recency, most recent tab first.
  getTabsByRecency() {
    const ids = Object.keys(this.tabIdToCounter);
    ids.sort((a, b) => this.tabIdToCounter[b] - this.tabIdToCounter[a]);
    return ids.map((id) => parseInt(id));
  }
}

Object.assign(globalThis, { TabRecency });

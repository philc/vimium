// TabRecency associates an integer with each tab id representing how recently it has been accessed.
// These are used to provide an initial recency-based ordering in the tabs vomnibar.
class TabRecency {
  constructor() {
    this.counter = 1;
    this.tabIdToCounter = {};

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
  }

  register(tabId) {
    this.counter++;
    this.tabIdToCounter[tabId] = this.counter;
  }

  deregister(tabId) {
    delete this.tabIdToCounter[tabId];
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

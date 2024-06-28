// TabRecency associates an integer with each tab id representing how recently it has been accessed.
// The order of tabs as tracked by TabRecency is used to provide a recency-based ordering in the
// tabs vomnibar.
//
// The values are persisted to chrome.storage.session so that they're not lost when the extension's
// background page is unloaded.
//
// Callers must await TabRecency.init before calling recencyScore or getTabsByRecency.
//
// In theory, the browser's tab.lastAccessed timestamp field should allow us to sort tabs by
// recency, but in practice it does not work across several edge cases. See the comments on #4368.
class TabRecency {
  constructor() {
    this.counter = 1;
    this.tabIdToCounter = {};
    this.loaded = false;
    this.queuedActions = [];
  }

  // Add listeners to chrome.tabs, and load the index from session storage.
  async init() {
    if (this.initPromise) {
      await this.initPromise;
      return;
    }
    let resolveFn;
    this.initPromise = new Promise((resolve, _reject) => {
      resolveFn = resolve;
    });

    chrome.tabs.onActivated.addListener((activeInfo) => {
      this.queueAction("register", activeInfo.tabId);
    });
    chrome.tabs.onRemoved.addListener((tabId) => {
      this.queueAction("deregister", tabId);
    });

    chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
      this.queueAction("deregister", removedTabId);
      this.queueAction("register", addedTabId);
    });

    chrome.windows.onFocusChanged.addListener(async (windowId) => {
      if (windowId == chrome.windows.WINDOW_ID_NONE) return;
      const tabs = await chrome.tabs.query({ windowId, active: true });
      if (tabs[0]) {
        this.queueAction("register", tabs[0].id);
      }
    });

    await this.loadFromStorage();
    while (this.queuedActions.length > 0) {
      const [action, tabId] = this.queuedActions.shift();
      this.handleAction(action, tabId);
    }
    this.loaded = true;
    resolveFn();
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
    if (this.counter < maxCounter) {
      this.counter = maxCounter;
    }

    this.tabIdToCounter = Object.assign({}, storage.tabRecency);

    // Remove any tab IDs which aren't currently loaded.
    const tabIds = new Set(tabs.map((t) => t.id));
    for (const id in this.tabIdToCounter) {
      if (!tabIds.has(parseInt(id))) {
        delete this.tabIdToCounter[id];
      }
    }
  }

  async saveToStorage() {
    await chrome.storage.session.set({ tabRecency: this.tabIdToCounter });
  }

  // - action: "register" or "unregister".
  queueAction(action, tabId) {
    if (!this.loaded) {
      this.queuedActions.push([action, tabId]);
    } else {
      this.handleAction(action, tabId);
    }
  }

  // - action: "register" or "unregister".
  handleAction(action, tabId) {
    if (action == "register") {
      this.register(tabId);
    } else if (action == "deregister") {
      this.deregister(tabId);
    } else {
      throw new Error(`Unexpected action type: ${action}`);
    }
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
    if (!this.loaded) throw new Error("TabRecency hasn't yet been loaded.");
    const tabCounter = this.tabIdToCounter[tabId];
    const isCurrentTab = tabCounter == this.counter;
    if (isCurrentTab) return 0;
    return (tabCounter ?? 1) / this.counter; // tabCounter may be null.
  }

  // Returns a list of tab Ids sorted by recency, most recent tab first.
  getTabsByRecency() {
    if (!this.loaded) throw new Error("TabRecency hasn't yet been loaded.");
    const ids = Object.keys(this.tabIdToCounter);
    ids.sort((a, b) => this.tabIdToCounter[b] - this.tabIdToCounter[a]);
    return ids.map((id) => parseInt(id));
  }
}

Object.assign(globalThis, { TabRecency });

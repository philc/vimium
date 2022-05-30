// NOTE(mrmr1993): This is under lib/ since it is used by both content scripts and iframes from pages/.
// This implements find-mode query history (using the "findModeRawQueryList" setting) as a list of raw queries,
// most recent first.
const FindModeHistory = {
  storage: (typeof chrome !== 'undefined' && chrome !== null ? chrome.storage.local : undefined), // Guard against chrome being undefined (in the HUD iframe).
  key: "findModeRawQueryList",
  max: 50,
  rawQueryList: null,

  init() {
    this.isIncognitoMode = typeof chrome !== 'undefined' && chrome !== null ? chrome.extension.inIncognitoContext : undefined;

    if (this.isIncognitoMode == null) { return; } // chrome is undefined in the HUD iframe during tests, so we do nothing.

    if (!this.rawQueryList) {
      this.rawQueryList = []; // Prevent repeated initialization.
      if (this.isIncognitoMode) { this.key = "findModeRawQueryListIncognito"; }
      this.storage.get(this.key, items => {
        if (!chrome.runtime.lastError) {
          if (items[this.key]) { this.rawQueryList = items[this.key]; }
          if (this.isIncognitoMode && !items[this.key]) {
            // This is the first incognito tab, so we need to initialize the incognito-mode query history.
            this.storage.get("findModeRawQueryList", items => {
              if (!chrome.runtime.lastError) {
                this.rawQueryList = items.findModeRawQueryList;
                this.storage.set({findModeRawQueryListIncognito: this.rawQueryList});
              }
            });
          }
        }
      });
    }

    chrome.storage.onChanged.addListener((changes, area) => {
      if (changes[this.key]) { this.rawQueryList = changes[this.key].newValue; }
    });
  },

  getQuery(index) {
    if (index == null) { index = 0; }
    return this.rawQueryList[index] || "";
  },

  saveQuery(query) {
    if (0 < query.length) {
      this.rawQueryList = this.refreshRawQueryList(query, this.rawQueryList);
      const newSetting = {};
      newSetting[this.key] = this.rawQueryList;
      this.storage.set(newSetting);
      // If there are any active incognito-mode tabs, then propagte this query to those tabs too.
      if (!this.isIncognitoMode) {
        this.storage.get("findModeRawQueryListIncognito", items => {
          if (!chrome.runtime.lastError && items.findModeRawQueryListIncognito) {
            this.storage.set({
              findModeRawQueryListIncognito: this.refreshRawQueryList(query, items.findModeRawQueryListIncognito)});
          }
        });
      }
    }
  },

  refreshRawQueryList(query, rawQueryList) {
    return ([query].concat(rawQueryList.filter(q => q !== query))).slice(0, this.max + 1);
  }
};

window.FindModeHistory = FindModeHistory;

// This // implements find-mode query history as a list of raw queries, most recent first.
// This is under lib/ since it is used by both content scripts and iframes from pages/.
const FindModeHistory = {
  storage: chrome.storage.session,
  key: "findModeRawQueryList",
  max: 50,
  rawQueryList: null,

  async init() {
    this.isIncognitoMode = chrome.extension.inIncognitoContext;

    if (!this.rawQueryList) {
      if (this.isIncognitoMode) this.key = "findModeRawQueryListIncognito";

      let result = await this.storage.get(this.key);
      if (this.isIncognitoMode) {
        // This is the first incognito tab, so we need to initialize the incognito-mode query
        // history.
        result = await this.storage.get("findModeRawQueryList");
        this.rawQueryList = result.findModeRawQueryList || [];
        this.storage.set({ findModeRawQueryListIncognito: this.rawQueryList });
      } else {
        this.rawQueryList = result[this.key] || [];
      }
    }

    chrome.storage.onChanged.addListener((changes, _area) => {
      if (changes[this.key]) {
        this.rawQueryList = changes[this.key].newValue;
      }
    });
  },

  getQuery(index) {
    if (index == null) index = 0;
    return this.rawQueryList[index] || "";
  },

  async saveQuery(query) {
    if (query.length == 0) return;
    this.rawQueryList = this.refreshRawQueryList(query, this.rawQueryList);
    const newSetting = {};
    newSetting[this.key] = this.rawQueryList;
    await this.storage.set(newSetting);
    // If there are any active incognito-mode tabs, then propagate this query to those tabs too.
    if (!this.isIncognitoMode) {
      const result = await this.storage.get("findModeRawQueryListIncognito");
      if (result.findModeRawQueryListIncognito) {
        await this.storage.set({
          findModeRawQueryListIncognito: this.refreshRawQueryList(
            query,
            result.findModeRawQueryListIncognito,
          ),
        });
      }
    }
  },

  refreshRawQueryList(query, rawQueryList) {
    return ([query].concat(rawQueryList.filter((q) => q !== query))).slice(0, this.max + 1);
  },
};

window.FindModeHistory = FindModeHistory;

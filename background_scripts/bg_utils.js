import {BaseEngine} from "./completion_engines.js";

const TIME_DELTA = 500; // Milliseconds.

// TabRecency associates a logical timestamp with each tab id. These are used to provide an initial
// recency-based ordering in the tabs vomnibar (which allows jumping quickly between
// recently-visited tabs).
class TabRecency {
  constructor() {
    this.timestamp = 1;
    this.current = -1;
    this.cache = {};
    this.lastVisited = null;
    this.lastVisitedTime = null;

    chrome.tabs.onActivated.addListener((activeInfo) => this.register(activeInfo.tabId));
    chrome.tabs.onRemoved.addListener((tabId) => this.deregister(tabId));

    chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
      this.deregister(removedTabId);
      this.register(addedTabId);
    });

    if (chrome.windows != null) {
      chrome.windows.onFocusChanged.addListener((wnd) => {
        if (wnd !== chrome.windows.WINDOW_ID_NONE) {
          chrome.tabs.query({ windowId: wnd, active: true }, (tabs) => {
            if (tabs[0]) {
              this.register(tabs[0].id);
            }
          });
        }
      });
    }
  }

  register(tabId) {
    const currentTime = new Date();
    // Register tabId if it's been visited for at least @timeDelta ms. Tabs which are visited only
    // for a very-short time (e.g. those passed through with `5J`) aren't registered as visited.
    if ((this.lastVisitedTime != null) && (TIME_DELTA <= (currentTime - this.lastVisitedTime))) {
      this.cache[this.lastVisited] = ++this.timestamp;
    }

    this.current = this.lastVisited = tabId;
    this.lastVisitedTime = currentTime;
  }

  deregister(tabId) {
    if (tabId === this.lastVisited) {
      // Ensure we don't register this tab, since it's going away.
      this.lastVisited = this.lastVisitedTime = null;
    }
    delete this.cache[tabId];
  }

  // Recently-visited tabs get a higher score (except the current tab, which gets a low score).
  recencyScore(tabId) {
    if (!this.cache[tabId]) {
      this.cache[tabId] = 1;
    }
    if (tabId === this.current) {
      return 0.0;
    } else {
      return this.cache[tabId] / this.timestamp;
    }
  }

  // Returns a list of tab Ids sorted by recency, most recent tab first.
  getTabsByRecency() {
    const tabIds = Object.keys(this.cache || {});
    tabIds.sort((a, b) => this.cache[b] - this.cache[a]);
    return tabIds.map((tId) => parseInt(tId));
  }
}

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

  async getFirefoxVersion() {
    return globalThis.browser ? (await browser.runtime.getBrowserInfo()).version : null;
  },

  // Remove comments and leading/trailing whitespace from a list of lines, and merge lines where the
  // last character on the preceding line is "\".
  parseLines(text) {
    return text.replace(/\\\n/g, "")
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => (line.length > 0) && !(Array.from('#"').includes(line[0])));
  },

  escapedEntities: {
    '"': "&quots;",
    "&": "&amp;",
    "'": "&apos;",
    "<": "&lt;",
    ">": "&gt;",
  },

  escapeAttribute(string) {
    return string.replace(/["&'<>]/g, (char) => BgUtils.escapedEntities[char]);
  },
};

// Utility for parsing and using the custom search-engine configuration. We re-use the previous
// parse if the search-engine configuration is unchanged.
const SearchEngines = {
  previousSearchEngines: null,
  searchEngines: null,

  refresh(searchEngines) {
    if ((this.previousSearchEngines == null) || (searchEngines !== this.previousSearchEngines)) {
      this.previousSearchEngines = searchEngines;
      this.searchEngines = new AsyncDataFetcher(function (callback) {
        CompletionSearch.clearCache();
        const engines = {};
        CompletionEngines = [...BuiltinCompletionEngines];
        for (let line of BgUtils.parseLines(searchEngines)) {
          const tokens = line.split(/\s+/);
          if (2 <= tokens.length) {
            const keyword = tokens[0].split(":")[0];
            const searchUrl = tokens[1];
            // Build and register a new completion engine using the @URL
            if (3 <= tokens.length && tokens[2].startsWith("@")) {
              const [_, engineUrl, jsonPath] = tokens[2].split("@");
              const engineRegexp = "^" + searchUrl.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
              class NewCompletionEngine extends BaseEngine {
                constructor() {
                  super({
                    engineUrl: engineUrl,
                    regexps: [engineRegexp],
                    example: {
                      searchUrl: searchUrl,
                      keyword: keyword,
                    },
                  });
                }
                parse(text) {
                  if (!jsonPath) return super.parse(text);
                  let data = JSON.parse(text);
                  let star = false;
                  for (const key of jsonPath.split(".")) {
                    if (key === "*") {
                      // TODO when ES2019: Replace with data=data.flat(1)
                      if (star) data = [].concat.apply([], data);
                      star = true;
                    } else if (star && data instanceof Array) {
                      star = false;
                      data = data.map(val => val[key]);
                    } else {
                      data = data[key];
                    }
                  }
                  return data;
                }
              }
              CompletionEngines.unshift(NewCompletionEngine);
              tokens.shift();
            }
            const description = tokens.slice(2).join(" ") || `search (${keyword})`;
            if (Utils.hasFullUrlPrefix(searchUrl) || Utils.hasJavascriptPrefix(searchUrl)) {
              engines[keyword] = { keyword, searchUrl, description };
            }
          }
        }

        callback(engines);
      });
    }
  },

  // Use the parsed search-engine configuration, possibly asynchronously.
  use(callback) {
    this.searchEngines.use(callback);
  },

  // Both set (refresh) the search-engine configuration and use it at the same time.
  refreshAndUse(searchEngines, callback) {
    this.refresh(searchEngines);
    this.use(callback);
  },
};

BgUtils.TIME_DELTA = TIME_DELTA; // Referenced by our tests.

globalThis.SearchEngines = SearchEngines;
globalThis.BgUtils = BgUtils;

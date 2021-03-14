const TIME_DELTA = 500; // Milliseconds.

// TabRecency associates a logical timestamp with each tab id.  These are used to provide an initial
// recency-based ordering in the tabs vomnibar (which allows jumping quickly between recently-visited tabs).
class TabRecency {

  constructor() {
    this.timestamp = 1;
    this.current = -1;
    this.cache = {};
    this.lastVisited = null;
    this.lastVisitedTime = null;
    this.jumpList = null;

    chrome.tabs.onActivated.addListener(activeInfo => this.register(activeInfo.tabId));
    chrome.tabs.onRemoved.addListener(tabId => this.deregister(tabId));

    chrome.tabs.onReplaced.addListener((addedTabId, removedTabId) => {
      this.deregister(removedTabId);
      this.register(addedTabId);
    });

    if (chrome.windows != null) {
      chrome.windows.onFocusChanged.addListener(wnd => {
        if (wnd !== chrome.windows.WINDOW_ID_NONE) {
          chrome.tabs.query({windowId: wnd, active: true}, tabs => {
            if (tabs[0])
              this.register(tabs[0].id);
          });
        }
      });
    }
  }

  getJumpBackTabId({count}) {
    let backTabId = -1;
    if (!this.jumpList) {
      // getTabsByRecency might not include the current tab, eg if it was just
      // opened. Tabs aren't added until they have been seen for some time and
      // then an event is fired (like navigating back to the window). Add the
      // current tab if it hasn't been added.
      const tabs = this.getTabsByRecency().reverse();
      if (tabs.length > 0 && tabs[tabs.length - 1] !== this.current) {
        tabs.push(this.current);
      }
      this.jumpList = new TabJumpList(tabs);
    }
    backTabId = this.jumpList.getJumpBackTabId({count});
    return backTabId === -1 ? this.current : backTabId;
  }

  getJumpForwardTabId({count}) {
    let forwardTabId = -1;
    if (this.jumpList) {
      forwardTabId = this.jumpList.getJumpForwardTabId({count});
    }
    return forwardTabId === -1 ? this.current : forwardTabId;
  }

  register(tabId) {
    const currentTime = new Date();
    // Register tabId if it has been visited for at least @timeDelta ms.  Tabs which are visited only for a
    // very-short time (e.g. those passed through with `5J`) aren't registered as visited at all.
    if ((this.lastVisitedTime != null) && (TIME_DELTA <= (currentTime - this.lastVisitedTime))) {
      this.cache[this.lastVisited] = ++this.timestamp;
    }

    if (this.jumpList && !this.jumpList.isCoherent(tabId)) {
      this.jumpList = null;
    }

    this.current = (this.lastVisited = tabId);
    this.lastVisitedTime = currentTime;
  }

  deregister(tabId) {
    if (tabId === this.lastVisited) {
      // Ensure we don't register this tab, since it's going away.
      this.lastVisited = (this.lastVisitedTime = null);
    }
    delete this.cache[tabId];

    if (this.jumpList) {
      const jumpListInvalidated = this.jumpList.deregister(tabId);
      if (jumpListInvalidated) this.jumpList = null;
    }
  }

  // Recently-visited tabs get a higher score (except the current tab, which gets a low score).
  recencyScore(tabId) {
    if (!this.cache[tabId])
      this.cache[tabId] = 1;
    if (tabId === this.current)
      return 0.0;
    else
      return this.cache[tabId] / this.timestamp;
  }

  // Returns a list of tab Ids sorted by recency, most recent tab first.
  getTabsByRecency() {
    const tabIds = Object.keys(this.cache || {});
    tabIds.sort((a,b) => this.cache[b] - this.cache[a]);
    return tabIds.map(tId => parseInt(tId));
  }
}

// TabJumpList maintains a list of visited tabs. When no jumps have occurred,
// the list is all open tabs--the current (i.e. most recently visited) tab is
// the last element. The tab visited the longest in the past is the 0th tab.
// Jumping backwards moves through the open tabs. The index is maintained,
// allowing jumping forward to move again back to newer tabs. A manual
// navigation through a mechanism other than a jump resets the jump list.
class TabJumpList {

  constructor(tabs) {
    this.tabs = tabs;
    this.activeIdx = tabs.length - 1;
    // Tabs can be deleted after a TabJumpList has flattened the tabs into an
    // array. Rather than O(N) look through the tabs, we'll just maintain
    // deleted IDs and skip them.
    this.deletedTabs = new Set();
  }

  isCoherent(currentTabId) {
    return this.tabs[this.activeIdx] === currentTabId;
  }

  // Returns true if deregistering this tab invalidates the jump list.
  deregister(tabId) {
    if (this.tabs[this.activeIdx] == tabId) return true;

    this.deletedTabs.add(tabId);
    return false;
  }

  getJumpBackTabId({count = 1}) {
    let candidateIdx = -1;
    let need = count;
    for (let i = this.activeIdx - 1; i >= 0; i--) {
      let candidateId = this.tabs[i];
      if (this.deletedTabs.has(candidateId)) {
        continue;
      }
      candidateIdx = i;
      need--;
      if (need <= 0) {
        break;
      }
    }

    if (candidateIdx === -1) {
      // We're at the oldest tab.
      return -1;
    }

    this.activeIdx = candidateIdx;
    return this.tabs[this.activeIdx];
  }

  getJumpForwardTabId({count = 1}) {
    let candidateIdx = -1;
    let need = count;
    for (let i = this.activeIdx + 1; i < this.tabs.length; i++) {
      let candidateId = this.tabs[i];
      if (this.deletedTabs.has(candidateId)) {
        continue;
      }
      candidateIdx = i;
      need--;
      if (need <= 0) {
        break;
      }
    }

    if (candidateIdx === -1) {
      // We're at the newest tab.
      return -1;
    }

    this.activeIdx = candidateIdx;
    return this.tabs[this.activeIdx];
  }
}

var BgUtils = {
  tabRecency: new TabRecency(),

  // Log messages to the extension's logging page, but only if that page is open.
  log: (function() {
    const loggingPageUrl = chrome.runtime.getURL("pages/logging.html");
    if (loggingPageUrl != null) { console.log(`Vimium logging URL:\n  ${loggingPageUrl}`); } // Do not output URL for tests.
    // For development, it's sometimes useful to automatically launch the logging page on reload.
    if (localStorage.autoLaunchLoggingPage) { chrome.windows.create({url: loggingPageUrl, focused: false}); }
    return function(message, sender = null) {
      for (let viewWindow of chrome.extension.getViews({type: "tab"})) {
        if (viewWindow.location.pathname === "/pages/logging.html") {
          // Don't log messages from the logging page itself.  We do this check late because most of the time
          // it's not needed.
          if ((sender != null ? sender.url : undefined) !== loggingPageUrl) {
            const date = new Date;
            let [hours, minutes, seconds, milliseconds] =
              [date.getHours(), date.getMinutes(), date.getSeconds(), date.getMilliseconds()];
            if (minutes < 10) { minutes = "0" + minutes; }
            if (seconds < 10) { seconds = "0" + seconds; }
            if (milliseconds < 10) { milliseconds = "00" + milliseconds; }
            if (milliseconds < 100) { milliseconds = "0" + milliseconds; }
            const dateString = `${hours}:${minutes}:${seconds}.${milliseconds}`;
            const logElement = viewWindow.document.getElementById("log-text");
            logElement.value += `${dateString}: ${message}\n`;
            logElement.scrollTop = 2000000000;
          }
        }
      }
    };
  })(),

  // Remove comments and leading/trailing whitespace from a list of lines, and merge lines where the last
  // character on the preceding line is "\".
  parseLines(text) {
    return text.replace(/\\\n/g, "")
      .split("\n")
      .map(line => line.trim())
      .filter(line => (line.length > 0) && !(Array.from('#"').includes(line[0])));
  },

  escapedEntities: {
    '"': "&quots;",
    '&': "&amp;",
    "'": "&apos;",
    "<": "&lt;",
    ">": "&gt;"
  },

  escapeAttribute(string) {
    return string.replace(/["&'<>]/g, char => BgUtils.escapedEntities[char]);
  }
};

// Utility for parsing and using the custom search-engine configuration.  We re-use the previous parse if the
// search-engine configuration is unchanged.
const SearchEngines = {
  previousSearchEngines: null,
  searchEngines: null,

  refresh(searchEngines) {
    if ((this.previousSearchEngines == null) || (searchEngines !== this.previousSearchEngines)) {
      this.previousSearchEngines = searchEngines;
      this.searchEngines = new AsyncDataFetcher(function(callback) {
        const engines = {};
        for (let line of BgUtils.parseLines(searchEngines)) {
          const tokens = line.split(/\s+/);
          if (2 <= tokens.length) {
            const keyword = tokens[0].split(":")[0];
            const searchUrl = tokens[1];
            const description = tokens.slice(2).join(" ") || `search (${keyword})`;
            if (Utils.hasFullUrlPrefix(searchUrl) || Utils.hasJavascriptPrefix(searchUrl))
              engines[keyword] = {keyword, searchUrl, description};
          }
        }

        callback(engines);
      });
    }
  },

  // Use the parsed search-engine configuration, possibly asynchronously.
  use(callback) { this.searchEngines.use(callback); },

  // Both set (refresh) the search-engine configuration and use it at the same time.
  refreshAndUse(searchEngines, callback) {
    this.refresh(searchEngines);
    this.use(callback);
  }
};

BgUtils.TIME_DELTA = TIME_DELTA; // Referenced by our tests.

global.SearchEngines = SearchEngines;
global.BgUtils = BgUtils;

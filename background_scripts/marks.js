import * as TabOperations from "./tab_operations.js";

const Marks = {
  // This returns the key which is used for storing mark locations in chrome.storage.sync.
  getLocationKey(markName) {
    return `vimiumGlobalMark|${markName}`;
  },

  // Get the part of a URL we use for matching here (that is, everything up to the first anchor).
  getBaseUrl(url) {
    return url.split("#")[0];
  },

  // Create a global mark. We record vimiumSecret with the mark so that we can tell later, when the
  // mark is used, whether this is the original Vimium session or a subsequent session. This affects
  // whether or not tabId can be considered valid.
  async create(req, sender) {
    const items = await chrome.storage.session.get("vimiumSecret");
    const markInfo = {
      vimiumSecret: items.vimiumSecret,
      markName: req.markName,
      url: this.getBaseUrl(sender.tab.url),
      tabId: sender.tab.id,
      scrollX: req.scrollX,
      scrollY: req.scrollY,
    };

    if ((markInfo.scrollX != null) && (markInfo.scrollY != null)) {
      this.saveMark(markInfo);
    } else {
      // The front-end frame hasn't provided the scroll position (because it's not the top frame
      // within its tab). We need to ask the top frame what its scroll position is.
      chrome.tabs.sendMessage(sender.tab.id, { handler: "getScrollPosition" }, (response) => {
        this.saveMark(
          Object.assign(markInfo, { scrollX: response.scrollX, scrollY: response.scrollY }),
        );
      });
    }
  },

  saveMark(markInfo) {
    const item = {};
    item[this.getLocationKey(markInfo.markName)] = markInfo;
    chrome.storage.local.set(item);
  },

  // Goto a global mark. We try to find the original tab. If we can't find that, then we try to find
  // another tab with the original URL, and use that. And if we can't find such an existing tab,
  // then we create a new one. Whichever of those we do, we then set the scroll position to the
  // original scroll position.
  async goto(req) {
    const vimiumSecret = (await chrome.storage.session.get("vimiumSecret"))["vimiumSecret"];
    const key = this.getLocationKey(req.markName);
    const items = await chrome.storage.local.get(key);
    const markInfo = items[key];
    if (markInfo.vimiumSecret !== vimiumSecret) {
      // This is a different Vimium instantiation, so markInfo.tabId is definitely out of date.
      Utils.debugLog("marks: vimiumSecret is incorrect.");
      await this.focusOrLaunch(markInfo, req);
    } else {
      // Check whether markInfo.tabId still exists. According to
      // https://developer.chrome.com/extensions/tabs, tab Ids are unqiue within a Chrome
      // session. So, if we find a match, we can use it.
      let tab;
      // This will throw an error if the tab doesn't exist.
      try {
        tab = await chrome.tabs.get(markInfo.tabId);
      } catch {
        // Swallow.
      }
      const originalTabStillExists = tab?.url && (markInfo.url === this.getBaseUrl(tab.url));
      if (originalTabStillExists) {
        await this.gotoPositionInTab(markInfo);
      } else {
        await this.focusOrLaunch(markInfo, req);
      }
    }
  },

  // Focus an existing tab and scroll to the given position within it.
  async gotoPositionInTab({ tabId, scrollX, scrollY }) {
    const tab = await chrome.tabs.update(tabId, { active: true });
    chrome.windows.update(tab.windowId, { focused: true });
    chrome.tabs.sendMessage(tabId, { handler: "setScrollPosition", scrollX, scrollY });
  },

  // The tab we're trying to find no longer exists. We either find another tab with a matching URL
  // and use it, or we create a new tab.
  async focusOrLaunch(markInfo, req) {
    // If we're not going to be scrolling to a particular position in the tab, then we choose all
    // tabs with a matching URL prefix. Otherwise, we require an exact match (because it doesn't
    // make sense to scroll unless there's an exact URL match).
    const markIsScrolled = markInfo.scrollX > 0 || markInfo.scrollY > 0;
    const query = markIsScrolled ? markInfo.url : `${markInfo.url}*`;
    const tabs = await chrome.tabs.query({ url: query });
    if (tabs.length > 0) {
      // There is at least one matching tab. Pick one and go to it.
      const tab = await this.pickTab(tabs);
      this.gotoPositionInTab(Object.assign(markInfo, { tabId: tab.id }));
    } else {
      // There is no existing matching tab. We'll have to create one.
      TabOperations.openUrlInNewTab(
        Object.assign(req, { url: this.getBaseUrl(markInfo.url) }),
        (tab) => {
          // Note. tabLoadedHandlers is defined in "main.js". The handler below will be called
          // when the tab is loaded, its DOM is ready and it registers with the background page.
          return tabLoadedHandlers[tab.id] = () =>
            this.gotoPositionInTab(Object.assign(markInfo, { tabId: tab.id }));
        },
      );
    }
  },

  // Given a list of tabs candidate tabs, pick one. Prefer tabs in the current window and tabs with
  // shorter (matching) URLs.
  async pickTab(tabs) {
    // NOTE(philc): We assume getCurrent() can return null, but I didn't confirm this. Also, it
    // should be impossible for the user to invoke Vimium-related keys if all windows are closed.
    const window = await chrome.windows.getCurrent();
    const windowId = window?.id;
    // Prefer tabs in the current window, if there are any.
    const tabsInWindow = tabs.filter((tab) => tab.windowId === windowId);
    if (tabsInWindow.length > 0) tabs = tabsInWindow;
    // If more than one tab remains and the current tab is still a candidate, then don't pick the
    // current tab (because jumping to it does nothing).
    if (tabs.length > 1) {
      tabs = tabs.filter((t) => !t.active);
    }

    // Prefer shorter URLs.
    tabs.sort((a, b) => a.url.length - b.url.length);
    return tabs[0];
  },
};

globalThis.Marks = Marks;

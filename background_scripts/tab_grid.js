// Data provider for the tab grid (the "showTabGrid" command, bound to Shift+D by default).
// The grid shows the current window's tabs, capped at TAB_GRID_MAX_TABS, with a thumbnail for
// each tab. Chrome can only capture a screenshot of the visible tab, so the active tab gets a
// live screenshot while the other tabs are represented by their favicons.

const TAB_GRID_MAX_TABS = 9;

// Picks which tabs to show in the grid. Tabs keep their tab-bar order; when there are more
// tabs than maxTabs, a window of maxTabs is shown which always includes the active tab.
function pickTabsForGrid(tabs, activeTabId, maxTabs = TAB_GRID_MAX_TABS) {
  const ordered = tabs.slice().sort((a, b) => a.index - b.index);
  if (ordered.length <= maxTabs) return ordered;
  const activePosition = Math.max(
    0,
    ordered.findIndex((tab) => tab.id == activeTabId),
  );
  const start = Math.min(
    Math.max(0, activePosition - Math.floor(maxTabs / 2)),
    ordered.length - maxTabs,
  );
  return ordered.slice(start, start + maxTabs);
}

// Message handler for "removeTabById" requests from the tab grid UI. Closes one tab by ID.
async function removeTabById({ id }) {
  await chrome.tabs.remove(id);
}

// Message handler for "getTabGridData" requests from the tab grid UI. Returns the tabs to show
// plus a screenshot of the active tab (or null when capturing fails).
async function getTabGridData(_request, sender) {
  const tabs = await chrome.tabs.query({ currentWindow: true });
  const visibleTabs = tabs.filter((tab) => !tab.hidden);
  const activeTabId = sender.tab?.id;
  const picked = pickTabsForGrid(visibleTabs, activeTabId);
  const descriptors = picked.map((tab) => ({
    id: tab.id,
    title: tab.title || "",
    url: tab.url || "",
    favIconUrl: tab.favIconUrl || null,
    active: tab.id == activeTabId,
  }));

  let activeTabThumbnail = null;
  if (typeof chrome.tabs.captureVisibleTab == "function") {
    try {
      activeTabThumbnail = await chrome.tabs.captureVisibleTab(sender.tab.windowId, {
        format: "jpeg",
        quality: 30,
      });
    } catch {
      activeTabThumbnail = null;
    }
  }
  return { tabs: descriptors, activeTabThumbnail };
}

export { getTabGridData, pickTabsForGrid, removeTabById, TAB_GRID_MAX_TABS };

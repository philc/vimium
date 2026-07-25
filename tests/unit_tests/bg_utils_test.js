import "./test_helper.js";
import "../../lib/url_utils.js";
import "../../background_scripts/tab_recency.js";
import * as bgUtils from "../../background_scripts/bg_utils.js";

context("getLastActiveTab", () => {
  setup(() => {
    stub(bgUtils.tabRecency, "init", () => Promise.resolve());
  });

  should("return the most recent valid tab, excluding excludeTabId", async () => {
    stub(bgUtils.tabRecency, "getTabsByRecency", () => [1, 2, 3]);
    stub(chrome.tabs, "query", () =>
      Promise.resolve([
        { id: 1, groupId: -1 },
        { id: 2, groupId: -1 },
        { id: 3, groupId: -1 },
      ]));
    const tab = await bgUtils.getLastActiveTab({ windowId: 1, excludeTabId: 1 });
    assert.equal(2, tab.id);
  });

  should("skip candidates that fail isValid", async () => {
    stub(bgUtils.tabRecency, "getTabsByRecency", () => [1, 2, 3]);
    stub(chrome.tabs, "query", () =>
      Promise.resolve([
        { id: 1, groupId: 5 },
        { id: 2, groupId: 5 },
        { id: 3, groupId: -1 },
      ]));
    const tab = await bgUtils.getLastActiveTab({
      windowId: 1,
      excludeTabId: 1,
      isValid: (t) => t.groupId === -1,
    });
    assert.equal(3, tab.id);
  });

  should("return null when no candidate matches", async () => {
    stub(bgUtils.tabRecency, "getTabsByRecency", () => [1, 2]);
    stub(chrome.tabs, "query", () =>
      Promise.resolve([
        { id: 1, groupId: 5 },
        { id: 2, groupId: 5 },
      ]));
    const tab = await bgUtils.getLastActiveTab({
      windowId: 1,
      excludeTabId: 1,
      isValid: (t) => t.groupId === -1,
    });
    assert.equal(null, tab);
  });
});

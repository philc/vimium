import "./test_helper.js";
import * as bgUtils from "../../background_scripts/bg_utils.js";
import {
  collapseAllTabGroups,
  collapseTabGroup,
  moveTab,
} from "../../background_scripts/tab_groups.js";

context("moveTab (>> / <<) past a collapsed group at the window edge", () => {
  let movedTo;

  setup(() => {
    movedTo = null;
    stub(chrome.tabs, "move", (_id, args) => {
      movedTo = args.index;
    });
    stub(chrome, "tabGroups", { get: () => ({ collapsed: true }) });
  });

  should("jump past a collapsed group flush against the right edge", async () => {
    const tabs = [
      { id: 1, index: 0, groupId: -1, pinned: false },
      { id: 2, index: 1, groupId: 99, pinned: false },
      { id: 3, index: 2, groupId: 99, pinned: false },
    ];
    stub(chrome.tabs, "query", () => tabs);
    await moveTab({ count: 1, tab: tabs[0], registryEntry: { command: "moveTabRight" } });
    assert.equal(2, movedTo); // lands at the last group tab's index, past the group
  });

  should("jump past a collapsed group flush against the left edge", async () => {
    const tabs = [
      { id: 1, index: 0, groupId: 99, pinned: false },
      { id: 2, index: 1, groupId: 99, pinned: false },
      { id: 3, index: 2, groupId: -1, pinned: false },
    ];
    stub(chrome.tabs, "query", () => tabs);
    await moveTab({ count: 1, tab: tabs[2], registryEntry: { command: "moveTabLeft" } });
    assert.equal(0, movedTo); // lands at the first group tab's index, before the group
  });
});

context("collapseTabGroup (za)", () => {
  let activatedId, collapsedGroupId;

  setup(() => {
    activatedId = null;
    collapsedGroupId = null;
    stub(bgUtils.tabRecency, "init", () => Promise.resolve());
    stub(chrome.tabs, "update", (id, _args) => {
      activatedId = id;
    });
    stub(chrome, "tabGroups", {
      update: (id, _args) => {
        collapsedGroupId = id;
      },
    });
  });

  should("prefer the last active tab outside the group over index proximity", async () => {
    const tab = { id: 2, index: 1, windowId: 1, groupId: 99 };
    const tabs = [
      { id: 1, index: 0, groupId: -1 },
      { id: 2, index: 1, groupId: 99 },
      { id: 3, index: 2, groupId: -1 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(bgUtils.tabRecency, "getTabsByRecency", () => [2, 1, 3]);
    await collapseTabGroup({ tab });
    assert.equal(1, activatedId); // recency prefers tab 1 over the nearer-by-index tab 3
    assert.equal(99, collapsedGroupId);
  });

  should("fall back to index proximity when recency has no valid candidate", async () => {
    const tab = { id: 2, index: 1, windowId: 1, groupId: 99 };
    const tabs = [
      { id: 1, index: 0, groupId: 99 },
      { id: 2, index: 1, groupId: 99 },
      { id: 3, index: 2, groupId: -1 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(bgUtils.tabRecency, "getTabsByRecency", () => []);
    await collapseTabGroup({ tab });
    assert.equal(3, activatedId);
  });

  should("create a new tab when neither recency nor index proximity find a candidate", async () => {
    const tab = { id: 1, index: 0, windowId: 1, groupId: 99 };
    const tabs = [{ id: 1, index: 0, groupId: 99 }];
    stub(chrome.tabs, "query", () => tabs);
    stub(bgUtils.tabRecency, "getTabsByRecency", () => []);
    stub(chrome.tabs, "create", () => Promise.resolve({ id: 42 }));
    await collapseTabGroup({ tab });
    assert.equal(42, activatedId);
  });
});

context("collapseAllTabGroups (zA)", () => {
  let activatedId, collapsedGroupIds;

  setup(() => {
    activatedId = null;
    collapsedGroupIds = [];
    stub(bgUtils.tabRecency, "init", () => Promise.resolve());
    stub(chrome.tabs, "update", (id, _args) => {
      activatedId = id;
    });
  });

  should("collapse every expanded group and land on the last active ungrouped tab", async () => {
    const tab = { id: 3, index: 2, windowId: 1, groupId: -1 };
    stub(chrome, "tabGroups", {
      query: () => [{ id: 10 }, { id: 20 }],
      update: (id, _args) => collapsedGroupIds.push(id),
    });
    const tabs = [
      { id: 1, index: 0, groupId: -1 },
      { id: 2, index: 1, groupId: 10 },
      { id: 3, index: 2, groupId: -1 },
      { id: 4, index: 3, groupId: -1 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(bgUtils.tabRecency, "getTabsByRecency", () => [3, 1, 4, 2]);
    await collapseAllTabGroups({ tab });
    assert.equal([10, 20], collapsedGroupIds);
    assert.equal(1, activatedId); // recency prefers tab 1 over the nearer-by-index tab 4
  });

  should("skip already-collapsed groups, and fall back to creating a new tab", async () => {
    const tab = { id: 1, index: 0, windowId: 1, groupId: -1 };
    stub(chrome, "tabGroups", {
      query: (args) => {
        assert.equal(false, args.collapsed);
        return [];
      },
      update: (id, _args) => collapsedGroupIds.push(id),
    });
    stub(chrome.tabs, "query", () => [{ id: 1, index: 0, groupId: -1 }]);
    stub(bgUtils.tabRecency, "getTabsByRecency", () => []);
    stub(chrome.tabs, "create", () => Promise.resolve({ id: 99 }));
    await collapseAllTabGroups({ tab });
    assert.equal([], collapsedGroupIds);
    assert.equal(99, activatedId);
  });

  should("fall back to index proximity when recency has no valid candidate", async () => {
    const tab = { id: 2, index: 1, windowId: 1, groupId: -1 };
    stub(chrome, "tabGroups", { query: () => [], update: () => {} });
    const tabs = [
      { id: 1, index: 0, groupId: 10 },
      { id: 2, index: 1, groupId: -1 },
      { id: 3, index: 2, groupId: -1 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(bgUtils.tabRecency, "getTabsByRecency", () => []);
    await collapseAllTabGroups({ tab });
    assert.equal(3, activatedId);
  });
});

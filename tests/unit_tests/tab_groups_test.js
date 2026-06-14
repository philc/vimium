import "./test_helper.js";
import "../../background_scripts/bg_utils.js";
import {
  moveTab,
  selectNextTabForGroup,
  selectPreviousTabForGroup,
} from "../../background_scripts/tab_groups.js";

function makeTabs(count, highlighted = []) {
  return Array.from({ length: count }, (_, i) => ({
    id: i + 1,
    index: i,
    windowId: 1,
    highlighted: highlighted.includes(i),
    groupId: -1,
  }));
}

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

context("selectNextTabForGroup (zz)", () => {
  let capturedHighlight;

  setup(() => {
    capturedHighlight = null;
    stub(chrome.tabs, "highlight", (args) => {
      capturedHighlight = args.tabs;
    });
  });

  should("extend right when only the anchor is selected", async () => {
    const tabs = makeTabs(5, [2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[2], count: 1 });
    assert.equal([2, 3], capturedHighlight);
  });

  should("extend further right when right side is already extended", async () => {
    const tabs = makeTabs(5, [2, 3]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[2], count: 1 });
    assert.equal([2, 3, 4], capturedHighlight);
  });

  should("shrink from left when left side is extended", async () => {
    const tabs = makeTabs(5, [1, 2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[2], count: 1 });
    assert.equal([2], capturedHighlight);
  });

  should("do nothing when anchor is at the last tab", async () => {
    const tabs = makeTabs(3, [2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[2], count: 1 });
    assert.equal(null, capturedHighlight);
  });

  should("do nothing when right extension already reaches the last tab", async () => {
    const tabs = makeTabs(3, [1, 2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[1], count: 1 });
    assert.equal(null, capturedHighlight);
  });

  should("extend right 3 tabs with count: 3", async () => {
    const tabs = makeTabs(6, [2]);
    let callCount = 0;
    stub(chrome.tabs, "query", () => {
      const highlighted = [2, ...Array.from({ length: callCount }, (_, i) => 3 + i)];
      callCount++;
      return makeTabs(6, highlighted);
    });
    await selectNextTabForGroup({ tab: tabs[2], count: 3 });
    assert.equal([2, 3, 4, 5], capturedHighlight);
  });
});

context("selectPreviousTabForGroup (ZZ)", () => {
  let capturedHighlight;

  setup(() => {
    capturedHighlight = null;
    stub(chrome.tabs, "highlight", (args) => {
      capturedHighlight = args.tabs;
    });
  });

  should("extend left when only the anchor is selected", async () => {
    const tabs = makeTabs(5, [2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[2], count: 1 });
    assert.equal([2, 1], capturedHighlight);
  });

  should("extend further left when left side is already extended", async () => {
    const tabs = makeTabs(5, [1, 2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[2], count: 1 });
    assert.equal([2, 1, 0], capturedHighlight);
  });

  should("shrink from right when right side is extended", async () => {
    const tabs = makeTabs(5, [2, 3]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[2], count: 1 });
    assert.equal([2], capturedHighlight);
  });

  should("do nothing when anchor is at the first tab", async () => {
    const tabs = makeTabs(3, [0]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[0], count: 1 });
    assert.equal(null, capturedHighlight);
  });

  should("do nothing when left extension already reaches the first tab", async () => {
    const tabs = makeTabs(3, [0, 1]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[1], count: 1 });
    assert.equal(null, capturedHighlight);
  });

  should("extend left 3 tabs with count: 3", async () => {
    const tabs = makeTabs(6, [3]);
    let callCount = 0;
    stub(chrome.tabs, "query", () => {
      const highlighted = [3, ...Array.from({ length: callCount }, (_, i) => 2 - i)];
      callCount++;
      return makeTabs(6, highlighted);
    });
    await selectPreviousTabForGroup({ tab: tabs[3], count: 3 });
    assert.equal([3, 1, 2, 0], capturedHighlight);
  });
});

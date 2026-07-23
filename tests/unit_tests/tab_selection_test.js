import "./test_helper.js";
import "../../background_scripts/bg_utils.js";
import {
  moveTabSelection,
  selectNextTabForGroup,
  selectPreviousTabForGroup,
} from "../../background_scripts/tab_selection.js";

function makeTabs(count, highlighted = []) {
  return Array.from({ length: count }, (_, i) => ({
    id: i + 1,
    index: i,
    windowId: 1,
    highlighted: highlighted.includes(i),
    pinned: false,
    groupId: -1,
  }));
}

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

context("moveTabSelection (>> / << with multi-tab selection)", () => {
  let movedId, movedToIndex;

  setup(() => {
    movedId = null;
    movedToIndex = null;
    stub(chrome.tabs, "move", (id, args) => {
      movedId = id;
      movedToIndex = args.index;
    });
  });

  should("move block right by placing the right neighbor before the block", async () => {
    // Tabs: [0, 1(sel), 2(sel), 3(sel), 4]
    const tabs = makeTabs(5, [1, 2, 3]);
    stub(chrome.tabs, "query", () => tabs);
    await moveTabSelection({
      count: 1,
      tab: tabs[2],
      registryEntry: { command: "moveTabRight" },
    });
    // Neighbor to the right of the block is tab id=5 (index 4).
    // It should be moved to index 1 (the left edge of the block).
    assert.equal(5, movedId);
    assert.equal(1, movedToIndex);
  });

  should("move block left by placing the left neighbor after the block", async () => {
    // Tabs: [0, 1(sel), 2(sel), 3(sel), 4]
    const tabs = makeTabs(5, [1, 2, 3]);
    stub(chrome.tabs, "query", () => tabs);
    await moveTabSelection({
      count: 1,
      tab: tabs[2],
      registryEntry: { command: "moveTabLeft" },
    });
    // Neighbor to the left of the block is tab id=1 (index 0).
    // It should be moved to index 3 (the right edge of the block).
    assert.equal(1, movedId);
    assert.equal(3, movedToIndex);
  });

  should("do nothing when block is at the right window edge", async () => {
    // Tabs: [0, 1(sel), 2(sel), 3(sel)]  — block already at the right edge
    const tabs = makeTabs(4, [1, 2, 3]);
    stub(chrome.tabs, "query", () => tabs);
    await moveTabSelection({
      count: 1,
      tab: tabs[2],
      registryEntry: { command: "moveTabRight" },
    });
    assert.equal(null, movedId);
  });

  should("do nothing when block is at the left window edge", async () => {
    // Tabs: [0(sel), 1(sel), 2(sel), 3]  — block already at the left edge
    const tabs = makeTabs(4, [0, 1, 2]);
    stub(chrome.tabs, "query", () => tabs);
    await moveTabSelection({
      count: 1,
      tab: tabs[1],
      registryEntry: { command: "moveTabLeft" },
    });
    assert.equal(null, movedId);
  });

  should("skip over a collapsed group to the right in one step", async () => {
    // Tabs: [0, 1(sel), 2(sel), 3(sel), 4(grp99), 5(grp99), 6]
    const tabs = [
      { id: 1, index: 0, windowId: 1, highlighted: false, pinned: false, groupId: -1 },
      { id: 2, index: 1, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 3, index: 2, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 4, index: 3, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 5, index: 4, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
      { id: 6, index: 5, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
      { id: 7, index: 6, windowId: 1, highlighted: false, pinned: false, groupId: -1 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(chrome, "tabGroups", { get: () => ({ collapsed: true }) });
    const moves = [];
    stub(chrome.tabs, "move", (id, args) => moves.push({ id, index: args.index }));
    await moveTabSelection({
      count: 1,
      tab: tabs[2],
      registryEntry: { command: "moveTabRight" },
    });
    // Rightmost first: id4→groupLast(5)-0=5, id3→5-1=4, id2→5-2=3. Group never touched.
    assert.equal([{ id: 4, index: 5 }, { id: 3, index: 4 }, { id: 2, index: 3 }], moves);
  });

  should("skip over a collapsed group to the left in one step", async () => {
    // Tabs: [0, 1(grp99), 2(grp99), 3(sel), 4(sel), 5(sel), 6]
    const tabs = [
      { id: 1, index: 0, windowId: 1, highlighted: false, pinned: false, groupId: -1 },
      { id: 2, index: 1, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
      { id: 3, index: 2, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
      { id: 4, index: 3, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 5, index: 4, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 6, index: 5, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 7, index: 6, windowId: 1, highlighted: false, pinned: false, groupId: -1 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(chrome, "tabGroups", { get: () => ({ collapsed: true }) });
    const moves = [];
    stub(chrome.tabs, "move", (id, args) => moves.push({ id, index: args.index }));
    await moveTabSelection({
      count: 1,
      tab: tabs[4],
      registryEntry: { command: "moveTabLeft" },
    });
    // Leftmost first: id4→groupFirst(1)+0=1, id5→1+1=2, id6→1+2=3. Group never touched.
    assert.equal([{ id: 4, index: 1 }, { id: 5, index: 2 }, { id: 6, index: 3 }], moves);
  });

  should("join an open group when moving the block right into it", async () => {
    let joinedTabIds = null;
    let joinedGroupId = null;
    stub(chrome.tabs, "group", ({ tabIds, groupId }) => {
      joinedTabIds = tabIds;
      joinedGroupId = groupId;
    });
    // Tabs: [0(sel), 1(sel), 2(sel), 3(grp99), 4(grp99)]
    const tabs = [
      { id: 1, index: 0, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 2, index: 1, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 3, index: 2, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 4, index: 3, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
      { id: 5, index: 4, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(chrome, "tabGroups", { get: () => ({ collapsed: false }) });
    await moveTabSelection({
      count: 1,
      tab: tabs[1],
      registryEntry: { command: "moveTabRight" },
    });
    assert.equal([1, 2, 3], joinedTabIds);
    assert.equal(99, joinedGroupId);
  });

  should("join an open group when moving the block left into it", async () => {
    let joinedTabIds = null;
    let joinedGroupId = null;
    stub(chrome.tabs, "group", ({ tabIds, groupId }) => {
      joinedTabIds = tabIds;
      joinedGroupId = groupId;
    });
    // Tabs: [0(grp99), 1(grp99), 2(sel), 3(sel), 4(sel)]
    const tabs = [
      { id: 1, index: 0, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
      { id: 2, index: 1, windowId: 1, highlighted: false, pinned: false, groupId: 99 },
      { id: 3, index: 2, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 4, index: 3, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
      { id: 5, index: 4, windowId: 1, highlighted: true, pinned: false, groupId: -1 },
    ];
    stub(chrome.tabs, "query", () => tabs);
    stub(chrome, "tabGroups", { get: () => ({ collapsed: false }) });
    await moveTabSelection({
      count: 1,
      tab: tabs[3],
      registryEntry: { command: "moveTabLeft" },
    });
    assert.equal([3, 4, 5], joinedTabIds);
    assert.equal(99, joinedGroupId);
  });

  should("move block right N times with count: N", async () => {
    const moves = [];
    stub(chrome.tabs, "move", (id, args) => {
      moves.push({ id, index: args.index });
    });
    // Block at [2,3,4] in a 9-tab window — always enough room on the right.
    // Return the same state on every query call; we just verify move is called 3 times.
    const tabs = makeTabs(9, [2, 3, 4]);
    stub(chrome.tabs, "query", () => tabs);
    await moveTabSelection({
      count: 3,
      tab: tabs[3],
      registryEntry: { command: "moveTabRight" },
    });
    assert.equal(3, moves.length);
  });
});

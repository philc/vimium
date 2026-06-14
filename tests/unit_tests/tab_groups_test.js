import "./test_helper.js";
import "../../background_scripts/bg_utils.js";
import { moveTab } from "../../background_scripts/tab_groups.js";

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


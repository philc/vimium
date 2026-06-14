import "./test_helper.js";
import "../../background_scripts/bg_utils.js";
import {
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
    await selectNextTabForGroup({ tab: tabs[2] });
    assert.equal([2, 3], capturedHighlight);
  });

  should("extend further right when right side is already extended", async () => {
    const tabs = makeTabs(5, [2, 3]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[2] });
    assert.equal([2, 3, 4], capturedHighlight);
  });

  should("shrink from left when left side is extended", async () => {
    const tabs = makeTabs(5, [1, 2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[2] });
    assert.equal([2], capturedHighlight);
  });

  should("do nothing when anchor is at the last tab", async () => {
    const tabs = makeTabs(3, [2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[2] });
    assert.equal(null, capturedHighlight);
  });

  should("do nothing when right extension already reaches the last tab", async () => {
    const tabs = makeTabs(3, [1, 2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectNextTabForGroup({ tab: tabs[1] });
    assert.equal(null, capturedHighlight);
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
    await selectPreviousTabForGroup({ tab: tabs[2] });
    assert.equal([2, 1], capturedHighlight);
  });

  should("extend further left when left side is already extended", async () => {
    const tabs = makeTabs(5, [1, 2]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[2] });
    assert.equal([2, 1, 0], capturedHighlight);
  });

  should("shrink from right when right side is extended", async () => {
    const tabs = makeTabs(5, [2, 3]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[2] });
    assert.equal([2], capturedHighlight);
  });

  should("do nothing when anchor is at the first tab", async () => {
    const tabs = makeTabs(3, [0]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[0] });
    assert.equal(null, capturedHighlight);
  });

  should("do nothing when left extension already reaches the first tab", async () => {
    const tabs = makeTabs(3, [0, 1]);
    stub(chrome.tabs, "query", () => tabs);
    await selectPreviousTabForGroup({ tab: tabs[1] });
    assert.equal(null, capturedHighlight);
  });
});

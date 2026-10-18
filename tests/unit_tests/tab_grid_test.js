import * as testHelper from "./test_helper.js";
import { withPromise } from "./test_helper.js";
import "../../lib/settings.js";
import "../../lib/utils.js";
import "../../lib/keyboard_utils.js";
import "../../lib/dom_utils.js";
import "../../lib/handler_stack.js";
import "../../content_scripts/mode.js";
import "../../content_scripts/mode_key_handler.js";
import "../../content_scripts/marks.js";
import "../../content_scripts/link_hints.js";
import "../../content_scripts/vomnibar.js";
import "../../content_scripts/hud.js";
import "../../content_scripts/tab_grid.js";
// Include mode_normal to check that the new command has been implemented.
import "../../content_scripts/mode_normal.js";
import { allCommands } from "../../background_scripts/all_commands.js";
import { defaultKeyMappings } from "../../background_scripts/commands.js";
import {
  getTabGridData,
  pickTabsForGrid,
  removeTabById,
  TAB_GRID_MAX_TABS,
} from "../../background_scripts/tab_grid.js";

context("tab grid command", () => {
  should("be registered in allCommands", () => {
    const command = allCommands.find((c) => c.name == "showTabGrid");
    assert.isTrue(command != null);
    assert.equal("tabs", command.group);
    assert.isTrue(command.topFrame);
    assert.isTrue(command.noRepeat);
    assert.isTrue(command.desc.length > 0);
  });

  should("be bound to shift+D (D) by default", () => {
    assert.equal("showTabGrid", defaultKeyMappings["D"]);
  });

  should("have a NormalModeCommands handler", () => {
    assert.equal("function", typeof NormalModeCommands.showTabGrid);
  });
});

context("pickTabsForGrid", () => {
  const makeTabs = (count, activeIndex) => {
    const tabs = [];
    for (let i = 0; i < count; i++) {
      tabs.push({ id: 100 + i, index: i, title: `Tab ${i}`, active: i == activeIndex });
    }
    return tabs;
  };

  should("expose a max of 9 tabs", () => {
    assert.equal(9, TAB_GRID_MAX_TABS);
  });

  should("return all tabs when there are 9 or fewer", () => {
    const tabs = makeTabs(5, 2);
    const picked = pickTabsForGrid(tabs, 102);
    assert.equal(5, picked.length);
    assert.equal([100, 101, 102, 103, 104], picked.map((t) => t.id));
  });

  should("cap the result at 9 tabs", () => {
    const tabs = makeTabs(15, 0);
    const picked = pickTabsForGrid(tabs, 100);
    assert.equal(9, picked.length);
  });

  should("include the active tab when it is beyond the first 9", () => {
    const tabs = makeTabs(15, 14);
    const picked = pickTabsForGrid(tabs, 114);
    assert.equal(9, picked.length);
    assert.isTrue(picked.some((t) => t.id == 114));
  });

  should("preserve tab-bar order", () => {
    const tabs = makeTabs(12, 11);
    const picked = pickTabsForGrid(tabs, 111);
    const ids = picked.map((t) => t.id);
    assert.equal(ids.slice().sort((a, b) => a - b), ids);
  });

  should("handle an empty tab list", () => {
    assert.equal([], pickTabsForGrid([], -1));
  });
});

context("getTabGridData", () => {
  const makeTabs = (count, activeIndex) => {
    const tabs = [];
    for (let i = 0; i < count; i++) {
      tabs.push({
        id: 100 + i,
        index: i,
        title: `Tab ${i}`,
        url: `https://example.com/${i}`,
        favIconUrl: `https://example.com/favicon${i}.ico`,
        active: i == activeIndex,
      });
    }
    return tabs;
  };
  const sender = { tab: { id: 105, windowId: 1 } };

  should("return at most 9 tab descriptors including the active tab", async () => {
    stub(chrome.tabs, "query", withPromise(() => makeTabs(12, 5)));
    stub(chrome.tabs, "captureVisibleTab", withPromise(() => "data:image/jpeg;base64,xxx"));
    const data = await getTabGridData({}, sender);
    assert.equal(9, data.tabs.length);
    assert.isTrue(data.tabs.some((t) => t.id == 105));
    assert.equal("data:image/jpeg;base64,xxx", data.activeTabThumbnail);
    const tab = data.tabs[0];
    assert.isTrue("id" in tab && "title" in tab && "url" in tab && "active" in tab);
  });

  should("return a null thumbnail when capturing the visible tab fails", async () => {
    stub(chrome.tabs, "query", withPromise(() => makeTabs(3, 0)));
    stub(
      chrome.tabs,
      "captureVisibleTab",
      withPromise(() => {
        throw new Error("cannot capture");
      }),
    );
    const data = await getTabGridData({}, sender);
    assert.equal(3, data.tabs.length);
    assert.equal(null, data.activeTabThumbnail);
  });

  should("return a null thumbnail when captureVisibleTab is unavailable", async () => {
    stub(chrome.tabs, "query", withPromise(() => makeTabs(3, 1)));
    stub(chrome.tabs, "captureVisibleTab", undefined);
    const data = await getTabGridData({}, sender);
    assert.equal(3, data.tabs.length);
    assert.equal(null, data.activeTabThumbnail);
  });

  should("skip hidden tabs", async () => {
    const tabs = makeTabs(3, 0);
    tabs[1].hidden = true;
    stub(chrome.tabs, "query", withPromise(() => tabs));
    stub(chrome.tabs, "captureVisibleTab", undefined);
    const data = await getTabGridData({}, sender);
    assert.equal([100, 102], data.tabs.map((t) => t.id));
  });
});

context("removeTabById", () => {
  should("close the given tab", async () => {
    let removedId = null;
    stub(
      chrome.tabs,
      "remove",
      withPromise((id) => {
        removedId = id;
      }),
    );
    await removeTabById({ id: 123 });
    assert.equal(123, removedId);
  });
});

context("TabGrid hint strings", () => {
  setup(async () => {
    await Settings.onLoaded();
  });

  teardown(async () => {
    await Settings.clear();
  });

  should("use the linkHintCharacters setting", () => {
    // Default linkHintCharacters is "sadfjklewcmpgh"; single-char hints come out sorted.
    assert.equal(["a", "d", "s"], globalThis.TabGrid.getHintStrings(3));
  });

  should("respect a custom linkHintCharacters setting", async () => {
    await Settings.set("linkHintCharacters", "xyz");
    assert.equal(["x", "y"], globalThis.TabGrid.getHintStrings(2));
  });

  should("fall back to the defaults when the setting is unusable", async () => {
    await Settings.set("linkHintCharacters", "q");
    assert.equal(["a", "s"], globalThis.TabGrid.getHintStrings(2));
  });

  should("match AlphabetHints.hintStrings", async () => {
    await Settings.set("linkHintCharacters", "abc");
    for (const count of [1, 3, 9, 12]) {
      assert.equal(
        new AlphabetHints().hintStrings(count),
        globalThis.TabGrid.buildHintStrings(count, "abc"),
      );
    }
  });
});

context("TabGrid frontend", () => {
  const makeDescriptors = (count, activeIndex) => {
    const tabs = [];
    for (let i = 0; i < count; i++) {
      tabs.push({
        id: 100 + i,
        title: `Tab ${i}`,
        url: `https://example.com/${i}`,
        favIconUrl: `https://example.com/favicon${i}.ico`,
        active: i == activeIndex,
      });
    }
    return tabs;
  };
  const hints = ["a", "s", "d", "f", "j", "k", "l", "e", "w"];

  setup(async () => {
    // Which page we load doesn't matter; we just need any DOM.
    await testHelper.jsdomStub("pages/help_dialog_page.html");
    await Settings.onLoaded();
    // The grid shows a mode indicator via the HUD; stub that out (individual tests can record it).
    stub(globalThis.HUD, "show", () => {});
  });

  teardown(async () => {
    globalThis.TabGrid.hide();
    Mode.reset();
    handlerStack.reset();
    await Settings.clear();
  });

  should("render one card per tab with uppercase hint markers", () => {
    const overlay = globalThis.TabGrid.buildGridElement(makeDescriptors(4, 0), null, hints);
    const cards = overlay.querySelectorAll(".vimium-tab-grid-card");
    assert.equal(4, cards.length);
    const badges = Array.from(overlay.querySelectorAll(".vimium-tab-grid-hint"))
      .map((el) => el.textContent);
    assert.equal(["A", "S", "D", "F"], badges);
    // Hint badges reuse link hints' marker class, so custom hint CSS applies to them.
    assert.isTrue(
      overlay.querySelector(".vimium-tab-grid-hint").classList.contains(
        "vimiumHintMarker",
      ),
    );
  });

  should("render at most 9 cards", () => {
    const overlay = globalThis.TabGrid.buildGridElement(makeDescriptors(12, 0), null, hints);
    assert.equal(9, overlay.querySelectorAll(".vimium-tab-grid-card").length);
  });

  should("insert titles as text, not HTML", () => {
    const tabs = makeDescriptors(1, 0);
    tabs[0].title = '<img src="x" onerror="alert(1)">';
    const overlay = globalThis.TabGrid.buildGridElement(tabs, null, hints);
    const titleEl = overlay.querySelector(".vimium-tab-grid-title");
    assert.equal('<img src="x" onerror="alert(1)">', titleEl.textContent);
    assert.equal(null, titleEl.querySelector("img"));
  });

  should("use the screenshot thumbnail for the active tab", () => {
    const overlay = globalThis.TabGrid.buildGridElement(
      makeDescriptors(2, 1),
      "data:image/jpeg;base64,xxx",
      hints,
    );
    const thumbs = overlay.querySelectorAll(".vimium-tab-grid-thumb img");
    assert.equal(2, thumbs.length);
    assert.equal("data:image/jpeg;base64,xxx", thumbs[1].getAttribute("src"));
    assert.equal("https://example.com/favicon0.ico", thumbs[0].getAttribute("src"));
  });

  should("show a placeholder when a tab has no thumbnail or favicon", () => {
    const tabs = makeDescriptors(1, 0);
    tabs[0].favIconUrl = null;
    const overlay = globalThis.TabGrid.buildGridElement(tabs, null, hints);
    assert.equal(null, overlay.querySelector(".vimium-tab-grid-thumb img"));
    assert.equal("T", overlay.querySelector(".vimium-tab-grid-placeholder").textContent);
  });

  should("only accept safe thumbnail URLs", () => {
    assert.isTrue(globalThis.TabGrid.isSafeThumbnailUrl("https://example.com/f.ico"));
    assert.isTrue(globalThis.TabGrid.isSafeThumbnailUrl("http://example.com/f.ico"));
    assert.isTrue(globalThis.TabGrid.isSafeThumbnailUrl("data:image/jpeg;base64,xxx"));
    assert.isFalse(globalThis.TabGrid.isSafeThumbnailUrl("javascript:alert(1)"));
    assert.isFalse(globalThis.TabGrid.isSafeThumbnailUrl(null));
    assert.isFalse(globalThis.TabGrid.isSafeThumbnailUrl(""));
  });

  should("compute arrow-key navigation within the grid", () => {
    const next = globalThis.TabGrid.nextIndex;
    assert.equal(1, next(0, "right", 9, 3));
    assert.equal(0, next(0, "left", 9, 3));
    assert.equal(3, next(0, "down", 9, 3));
    assert.equal(0, next(0, "up", 9, 3));
    assert.equal(8, next(8, "right", 9, 3));
    assert.equal(7, next(8, "left", 9, 3));
    assert.equal(5, next(8, "up", 9, 3));
    assert.equal(8, next(5, "down", 9, 3));
    assert.equal(4, next(4, "down", 5, 3));
  });

  should("select the tab matching a typed hint character", () => {
    let selectedId = null;
    stub(globalThis.TabGrid, "selectTab", (id) => {
      selectedId = id;
    });
    globalThis.TabGrid.tabs = makeDescriptors(4, 0);
    globalThis.TabGrid.hintStrings = ["a", "s", "d", "f"];
    globalThis.TabGrid.hintKeystrokeQueue = [];
    globalThis.TabGrid.onKeyDown({ key: "s" });
    assert.equal(101, selectedId);
  });

  should("narrow multi-character hints and select on a unique match", () => {
    let selectedId = null;
    stub(globalThis.TabGrid, "selectTab", (id) => {
      selectedId = id;
    });
    globalThis.TabGrid.tabs = makeDescriptors(3, 0);
    globalThis.TabGrid.hintStrings = ["sa", "sd", "f"];
    globalThis.TabGrid.hintKeystrokeQueue = [];
    globalThis.TabGrid.onKeyDown({ key: "s" });
    assert.equal(null, selectedId);
    assert.equal(["s"], globalThis.TabGrid.hintKeystrokeQueue);
    globalThis.TabGrid.onKeyDown({ key: "d" });
    assert.equal(101, selectedId);
  });

  should("hide the grid when no hint matches", () => {
    let selectedId = null;
    let hidden = false;
    stub(globalThis.TabGrid, "selectTab", (id) => {
      selectedId = id;
    });
    stub(globalThis.TabGrid, "hide", () => {
      hidden = true;
    });
    globalThis.TabGrid.tabs = makeDescriptors(2, 0);
    globalThis.TabGrid.hintStrings = ["a", "s"];
    globalThis.TabGrid.hintKeystrokeQueue = [];
    globalThis.TabGrid.onKeyDown({ key: "z" });
    assert.equal(null, selectedId);
    assert.isTrue(hidden);
  });

  should("close the highlighted tab with x when x is not a hint", () => {
    let closedId = null;
    stub(globalThis.TabGrid, "closeTab", (id) => {
      closedId = id;
    });
    globalThis.TabGrid.tabs = makeDescriptors(2, 0);
    globalThis.TabGrid.hintStrings = ["a", "s"];
    globalThis.TabGrid.hintKeystrokeQueue = [];
    globalThis.TabGrid.selectedIndex = 1;
    globalThis.TabGrid.onKeyDown({ key: "x" });
    assert.equal(101, closedId);
  });

  should("prefer hint matching over the x close key", () => {
    let selectedId = null;
    let closedId = null;
    stub(globalThis.TabGrid, "selectTab", (id) => {
      selectedId = id;
    });
    stub(globalThis.TabGrid, "closeTab", (id) => {
      closedId = id;
    });
    globalThis.TabGrid.tabs = makeDescriptors(2, 0);
    globalThis.TabGrid.hintStrings = ["x", "y"];
    globalThis.TabGrid.hintKeystrokeQueue = [];
    globalThis.TabGrid.onKeyDown({ key: "x" });
    assert.equal(100, selectedId);
    assert.equal(null, closedId);
  });

  should("close the highlighted tab with Delete", () => {
    let closedId = null;
    stub(globalThis.TabGrid, "closeTab", (id) => {
      closedId = id;
    });
    globalThis.TabGrid.tabs = makeDescriptors(3, 0);
    globalThis.TabGrid.hintStrings = ["a", "s", "d"];
    globalThis.TabGrid.hintKeystrokeQueue = [];
    globalThis.TabGrid.selectedIndex = 2;
    globalThis.TabGrid.onKeyDown({ key: "Delete" });
    assert.equal(102, closedId);
  });

  should("pop hint characters with Backspace, hiding when empty", () => {
    let hidden = false;
    stub(globalThis.TabGrid, "hide", () => {
      hidden = true;
    });
    globalThis.TabGrid.tabs = makeDescriptors(3, 0);
    globalThis.TabGrid.hintStrings = ["sa", "sd", "f"];
    globalThis.TabGrid.hintKeystrokeQueue = ["s"];
    globalThis.TabGrid.onKeyDown({ key: "Backspace" });
    assert.equal([], globalThis.TabGrid.hintKeystrokeQueue);
    assert.isFalse(hidden);
    globalThis.TabGrid.onKeyDown({ key: "Backspace" });
    assert.isTrue(hidden);
  });

  should("hide non-matching cards while typing a multi-character hint", async () => {
    await Settings.set("linkHintCharacters", "ab");
    let selectedId = null;
    const indicators = [];
    stub(globalThis.TabGrid, "selectTab", (id) => {
      selectedId = id;
    });
    stub(globalThis.HUD, "show", (text) => indicators.push(text));
    stub(
      chrome.runtime,
      "sendMessage",
      withPromise(() => ({ tabs: makeDescriptors(3, 0), activeTabThumbnail: null })),
    );
    await globalThis.TabGrid.show();
    // With hint characters "ab", 3 tabs get hints ["aa", "b", "ab"].
    assert.equal(["aa", "b", "ab"], globalThis.TabGrid.hintStrings);
    globalThis.TabGrid.onKeyDown({ key: "a" });
    assert.equal(null, selectedId);
    const cards = globalThis.document.querySelectorAll(".vimium-tab-grid-card");
    assert.equal("", cards[0].style.display);
    assert.equal("none", cards[1].style.display);
    assert.equal("", cards[2].style.display);
    // The typed prefix is highlighted like in link hints.
    assert.isTrue(
      cards[0].querySelector(".vimium-tab-grid-hint span").classList.contains(
        "matchingCharacter",
      ),
    );
    // The mode indicator shows the typed characters, like link hints do.
    assert.equal(`Tab grid: "a".`, indicators[indicators.length - 1]);
    globalThis.TabGrid.onKeyDown({ key: "a" });
    assert.equal(100, selectedId);
  });

  should("render a close button per card that closes only that tab", () => {
    let selectedId = null;
    let closedId = null;
    stub(globalThis.TabGrid, "selectTab", (id) => {
      selectedId = id;
    });
    stub(globalThis.TabGrid, "closeTab", (id) => {
      closedId = id;
    });
    const overlay = globalThis.TabGrid.buildGridElement(makeDescriptors(2, 0), null, hints);
    globalThis.document.documentElement.appendChild(overlay);
    const closeButtons = overlay.querySelectorAll(".vimium-tab-grid-close-tab");
    assert.equal(2, closeButtons.length);
    closeButtons[1].click();
    assert.equal(101, closedId);
    assert.equal(null, selectedId);
    overlay.remove();
  });

  should("show and hide the overlay", async () => {
    stub(
      chrome.runtime,
      "sendMessage",
      withPromise(() => ({ tabs: makeDescriptors(3, 1), activeTabThumbnail: null })),
    );
    assert.isFalse(globalThis.TabGrid.isShowing());
    await globalThis.TabGrid.show();
    assert.isTrue(globalThis.TabGrid.isShowing());
    const overlay = globalThis.document.querySelector("#vimium-tab-grid-overlay");
    assert.isTrue(overlay != null);
    assert.equal(3, overlay.querySelectorAll(".vimium-tab-grid-card").length);
    assert.equal(3, overlay.querySelectorAll(".vimium-tab-grid-hint").length);
    globalThis.TabGrid.hide();
    assert.isFalse(globalThis.TabGrid.isShowing());
    assert.equal(null, globalThis.document.querySelector("#vimium-tab-grid-overlay"));
  });

  should("close a tab without closing the grid", async () => {
    let removedId = null;
    let gridDataRequests = 0;
    stub(
      chrome.runtime,
      "sendMessage",
      withPromise((message) => {
        if (message.handler == "removeTabById") {
          removedId = message.id;
          return {};
        }
        gridDataRequests++;
        return { tabs: makeDescriptors(3, 0), activeTabThumbnail: null };
      }),
    );
    await globalThis.TabGrid.show();
    assert.equal(3, globalThis.document.querySelectorAll(".vimium-tab-grid-card").length);
    // With the default hint characters, 3 tabs get hints ["a", "d", "s"].
    assert.equal(["a", "d", "s"], globalThis.TabGrid.hintStrings);
    globalThis.TabGrid.selectedIndex = 2;
    await globalThis.TabGrid.closeTab(101);
    assert.equal(101, removedId);
    assert.isTrue(globalThis.TabGrid.isShowing());
    // Only that tab's card is gone; the grid is not rebuilt (no refetch, hints stay stable).
    assert.equal(1, gridDataRequests);
    assert.equal(2, globalThis.document.querySelectorAll(".vimium-tab-grid-card").length);
    assert.equal(["a", "s"], globalThis.TabGrid.hintStrings);
    const badges = Array.from(globalThis.document.querySelectorAll(".vimium-tab-grid-hint"))
      .map((el) => el.textContent);
    assert.equal(["A", "S"], badges);
    // The selection clamps onto a remaining card.
    assert.equal(1, globalThis.TabGrid.selectedIndex);
    const cards = globalThis.document.querySelectorAll(".vimium-tab-grid-card");
    assert.isFalse(cards[0].classList.contains("vimium-tab-grid-selected"));
    assert.isTrue(cards[1].classList.contains("vimium-tab-grid-selected"));
  });

  should("hide the grid when closing the active tab", async () => {
    let removedId = null;
    stub(
      chrome.runtime,
      "sendMessage",
      withPromise((message) => {
        if (message.handler == "removeTabById") {
          removedId = message.id;
          return {};
        }
        return { tabs: makeDescriptors(2, 0), activeTabThumbnail: null };
      }),
    );
    await globalThis.TabGrid.show();
    await globalThis.TabGrid.closeTab(100);
    assert.equal(100, removedId);
    assert.isFalse(globalThis.TabGrid.isShowing());
  });
});

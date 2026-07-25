import "./test_helper.js";
import "../../background_scripts/tab_recency.js";
import "../../background_scripts/bg_utils.js";
import {
  TabGroupCompleter,
  TabGroupAssignCompleter,
  TabGroupColorCompleter,
} from "../../background_scripts/completion/group_completer.js";

async function filterCompleter(completer, queryTerms) {
  return await completer.filter({ queryTerms, query: queryTerms.join(" ") });
}

const testGroups = [
  { id: 10, title: "Work", color: "blue" },
  { id: 20, title: "", color: "orange" },
];
const testTabs = [
  { id: 1, index: 0, groupId: 10, url: "http://work.com" },
  { id: 2, index: 1, groupId: 20, url: "http://test.com" },
];

context("TabGroupCompleter", () => {
  setup(() => {
    stub(chrome.windows, "getLastFocused", () => ({ id: 1 }));
    stub(chrome, "tabGroups", { query: () => testGroups });
    stub(chrome.tabs, "query", () => testTabs);
  });

  should("return all groups when query is empty", async () => {
    const results = await filterCompleter(new TabGroupCompleter(), []);
    assert.equal(2, results.length);
  });

  should("filter groups by title", async () => {
    const results = await filterCompleter(new TabGroupCompleter(), ["work"]);
    assert.equal(1, results.length);
    assert.equal("Work", results[0].title);
  });

  should("filter groups by color", async () => {
    const results = await filterCompleter(new TabGroupCompleter(), ["blue"]);
    assert.equal(1, results.length);
    assert.equal("blue", results[0].description);
  });

  should("return empty when no groups match", async () => {
    const results = await filterCompleter(new TabGroupCompleter(), ["nonexistent"]);
    assert.equal(0, results.length);
  });

  should("set tabId to the first tab in the group", async () => {
    const results = await filterCompleter(new TabGroupCompleter(), []);
    assert.equal(1, results[0].tabId);
    assert.equal(2, results[1].tabId);
  });

  should("include a color swatch in the html", async () => {
    const results = await filterCompleter(new TabGroupCompleter(), []);
    assert.isTrue(results[0].html.includes("group-color-swatch"));
    assert.isTrue(results[0].html.includes("background:#1A73E8")); // blue
    assert.isTrue(results[1].html.includes("background:#E37400")); // orange
  });

  should("show group name in title and color name in source", async () => {
    const results = await filterCompleter(new TabGroupCompleter(), []);
    assert.isTrue(results[0].html.includes(">Work<")); // named group title
    assert.isTrue(results[1].html.includes(">(orange)<")); // unnamed group falls back to (color)
  });
});

context("TabGroupAssignCompleter", () => {
  setup(() => {
    stub(chrome.windows, "getLastFocused", () => ({ id: 1 }));
    stub(chrome, "tabGroups", { query: () => testGroups });
    stub(chrome.tabs, "query", () => testTabs);
  });

  should("return existing groups when query is empty", async () => {
    const results = await filterCompleter(new TabGroupAssignCompleter(), []);
    assert.equal(2, results.length);
    assert.isTrue(results.every((r) => r.groupData?.action === "addToGroup"));
  });

  should("include a Create entry when query does not empty", async () => {
    const results = await filterCompleter(new TabGroupAssignCompleter(), ["newgroup"]);
    const create = results.find((r) => r.groupData?.action === "createGroup");
    assert.isTrue(create != null);
    assert.equal("newgroup", create.groupData.name);
  });

  should("place the Create entry after existing matches", async () => {
    const results = await filterCompleter(new TabGroupAssignCompleter(), ["work"]);
    assert.equal("createGroup", results[results.length - 1].groupData.action);
  });

  should("set groupId correctly on addToGroup entries", async () => {
    const results = await filterCompleter(new TabGroupAssignCompleter(), []);
    assert.equal(10, results[0].groupData.groupId);
    assert.equal(20, results[1].groupData.groupId);
  });

  should("include color swatches for existing group entries", async () => {
    const results = await filterCompleter(new TabGroupAssignCompleter(), []);
    assert.isTrue(results[0].html.includes("group-color-swatch"));
  });

  should("filter existing groups by title when query matches", async () => {
    const results = await filterCompleter(new TabGroupAssignCompleter(), ["work"]);
    const existing = results.filter((r) => r.groupData?.action === "addToGroup");
    assert.equal(1, existing.length);
    assert.equal("Work", existing[0].title);
  });
});

context("TabGroupColorCompleter", () => {
  should("return all 9 colors when query is empty", async () => {
    const results = await filterCompleter(new TabGroupColorCompleter(), []);
    assert.equal(9, results.length);
  });

  should("filter colors by name prefix", async () => {
    const results = await filterCompleter(new TabGroupColorCompleter(), ["bl"]);
    assert.equal(1, results.length);
    assert.equal("blue", results[0].title);
  });

  should("return empty when no color matches", async () => {
    const results = await filterCompleter(new TabGroupColorCompleter(), ["xyz"]);
    assert.equal(0, results.length);
  });

  should("set a setColor action on every suggestion", async () => {
    const results = await filterCompleter(new TabGroupColorCompleter(), []);
    assert.isTrue(results.every((r) => r.groupData?.action === "setColor"));
    assert.isTrue(results.every((r) => typeof r.groupData.color === "string"));
  });

  should("preserve the GROUP_COLORS order", async () => {
    const results = await filterCompleter(new TabGroupColorCompleter(), []);
    assert.equal("grey", results[0].groupData.color);
    assert.equal("orange", results[results.length - 1].groupData.color);
  });

  should("include a color swatch in the html", async () => {
    const results = await filterCompleter(new TabGroupColorCompleter(), []);
    const grey = results.find((r) => r.groupData.color === "grey");
    assert.isTrue(grey.html.includes("group-color-swatch"));
    assert.isTrue(grey.html.includes("background:#5F6368"));
  });
});

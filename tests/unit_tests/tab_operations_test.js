import "./test_helper.js";
import "../../lib/settings.js";
import * as to from "../../background_scripts/tab_operations.js";

context("TabOperations openurlInCurrentTab", () => {
  should("open a regular URL", async () => {
    let url = null;
    stub(chrome.tabs, "update", (id, args) => {
      url = args.url;
    });
    const expected = "http://example.com";
    await to.openUrlInCurrentTab({ url: expected });
    assert.equal(expected, url);
  });

  should("open a non-URL in the default search engine", async () => {
    let searchQuery = null;
    stub(chrome.search, "query", (queryInfo) => {
      searchQuery = queryInfo.text;
    });
    const expected = "example query";
    await to.openUrlInCurrentTab({ url: expected });
    assert.equal(expected, searchQuery);
  });

  should("open a javascript URL", async () => {
    let details = null;
    // NOTE(philc): This is a shallow test.
    stub(chrome.scripting, "executeScript", (_details) => {
      details = _details;
    });
    const expected = "javascript:console.log('hello')";
    await to.openUrlInCurrentTab({ url: expected }, { frameId: 0 });
    assert.equal(expected, details.args[0]);
  });

  should("allow opening a javascript URL requested from the vomnibar's iframe", async () => {
    let details = null;
    stub(chrome.scripting, "executeScript", (_details) => {
      details = _details;
    });
    const expected = "javascript:console.log('hello')";
    // The vomnibar's iframe is a distinct frame with its own (non-zero) frameId, so it's
    // identified as trusted via its chrome-extension:// URL rather than via frameId.
    const sender = { frameId: 7, url: "chrome-extension://abc/pages/vomnibar_page.html" };
    await to.openUrlInCurrentTab({ url: expected }, sender);
    assert.equal(expected, details.args[0]);
  });

  should("disallow opening a javascript URL requested from an untrusted subframe", async () => {
    let called = false;
    stub(console, "warn", () => {}); // Silence the warning during this test.
    stub(chrome.scripting, "executeScript", () => {
      called = true;
    });
    const url = "javascript:console.log('hello')";
    // Simulates a cross-origin subframe (not the top frame, not one of Vimium's own pages).
    const sender = { frameId: 5, url: "https://attacker.example.com/iframe.html" };
    await to.openUrlInCurrentTab({ url }, sender);
    assert.isFalse(called);
  });
});

context("TabOperations openUrlInNewTab", () => {
  should("open a regular URL", async () => {
    let config = null;
    stub(chrome.tabs, "create", (_config) => {
      config = _config;
      const newTab = { url: config.url };
      return newTab;
    });
    const expected = "http://example.com";
    const tab = await to.openUrlInNewTab({
      tab: { index: 1 },
      position: "after",
      url: expected,
    });
    assert.equal(2, config.index);
    assert.equal(expected, tab.url);
  });

  should("open a non-URL in the default search engine", async () => {
    let createConfig, queryInfo;
    stub(chrome.tabs, "create", (config) => {
      createConfig = config;
      const newTab = { id: config.index };
      return newTab;
    });
    stub(chrome.search, "query", (info) => {
      queryInfo = info;
    });
    await to.openUrlInNewTab({
      tab: { index: 1 },
      position: "after",
      url: "example query",
    });
    assert.equal("data:text/html,<html></html>", createConfig.url);
    assert.equal(2, createConfig.index);
    assert.equal("example query", queryInfo.text);
    assert.equal(2, queryInfo.tabId);
  });
});

context("TabOperations openUrlInNewWindow", () => {
  should("open a regular URL in a new window", async () => {
    let windowConfig = null;
    stub(chrome.windows, "create", (config) => {
      windowConfig = config;
    });
    const expected = "http://example.com";
    await to.openUrlInNewWindow({ url: expected });
    assert.equal(expected, windowConfig.url);
    assert.isTrue(windowConfig.focused);
  });

  should("omit about:newtab URL in window config", async () => {
    let windowConfig = null;
    stub(chrome.windows, "create", (config) => {
      windowConfig = config;
    });
    await to.openUrlInNewWindow({ url: "about:newtab" });
    // about:newtab matches chromeNewTabUrl, so the url should be omitted.
    // Before the fix, this threw ReferenceError: tabConfig is not defined.
    assert.isFalse("url" in windowConfig);
  });
});

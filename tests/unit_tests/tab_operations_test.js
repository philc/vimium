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
    await to.openUrlInCurrentTab({ url: expected });
    assert.equal(expected, details.args[0]);
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

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

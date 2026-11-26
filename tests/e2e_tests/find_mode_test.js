import { context, setup, should, teardown } from "../vendor/shoulda.js";
import * as e2e from "./harness.js";

context("find mode", () => {
  setup(e2e.setup);
  teardown(e2e.teardown);

  should("select the matching text", async ({ tab }) => {
    await tab.load(`<p>haystack haystack needle haystack</p>`);
    await tab.keys("/");
    await tab.waitFor(async () => (await tab.hud())?.findMode);
    await tab.type("needle");
    await tab.keys("<enter>");
    await tab.waitFor(() => tab.evaluate(() => getSelection().toString() == "needle"));
  });

  should("reveal the selected match in nested scroll panes", async ({ tab }) => {
    await tab.load(`
      <div id="outer" style="height: 100px; overflow: auto">
        <div style="height: 180px"></div>
        <div id="inner" style="height: 100px; overflow: auto">
          <p id="first">needle</p>
          <div style="height: 180px"></div>
          <p id="second">needle</p>
        </div>
      </div>
    `);
    const isRevealed = (id) => {
      return tab.evaluate((id) => {
        const selection = getSelection();
        if (selection.anchorNode?.parentElement.id !== id) {
          return false;
        }
        const match = selection.getRangeAt(0).getBoundingClientRect();
        return ["outer", "inner"].every((pane) => {
          const bounds = document.getElementById(pane).getBoundingClientRect();
          return match.top >= bounds.top && match.bottom <= bounds.bottom;
        });
      }, id);
    };

    await tab.keys("/");
    await tab.waitFor(async () => (await tab.hud())?.findMode);
    await tab.type("needle");
    await tab.keys("<enter>");
    await tab.waitFor(() => isRevealed("first"));
    await tab.keys("n");
    await tab.waitFor(() => isRevealed("second"));
    await tab.keys("N");
    await tab.waitFor(() => isRevealed("first"));
  });

  should("find text inside a stylesheet-defined display: contents element", async ({ tab }) => {
    await tab.load(`
      <style>.contents { display: contents; }</style>
      <div class="contents"><p>Find this needle.</p></div>
    `);
    await tab.keys("/");
    await tab.waitFor(async () => (await tab.hud())?.findMode);
    await tab.type("needle");
    await tab.waitFor(() => tab.evaluate(() => getSelection().toString() == "needle"));
  });
});

import { assert, context, setup, should, teardown } from "../vendor/shoulda.js";
import * as e2e from "./harness.js";

context("find mode", () => {
  setup(e2e.setup);
  teardown(e2e.teardown);

  should("leave a caret at the start of the match, as Vim does", async ({ tab }) => {
    await tab.load(`<p>haystack haystack needle haystack</p>`);
    await tab.keys("/");
    await tab.waitFor(async () => (await tab.hud())?.findMode);
    await tab.type("needle");
    await tab.keys("<enter>");
    await tab.waitFor(() =>
      tab.evaluate(() => getSelection().isCollapsed && getSelection().anchorOffset == 18)
    );
  });

  should("keep the keys typed before the HUD has the focus", async ({ tab }) => {
    await tab.load(`<p>needle</p>`);
    await tab.keys("/");
    await tab.type("needle");
    await tab.waitFor(async () => (await tab.hud())?.text == "needle (1 Match)");
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
    const activeMatch = () =>
      tab.evaluate(() => [...CSS.highlights.get("vimium-find-active") ?? []].join());
    await tab.waitFor(async () => (await activeMatch()) == "needle");
  });

  should("find text the page adds while find mode is open", async ({ tab }) => {
    await tab.load(`<p>needle</p>`);
    await tab.keys("/");
    await tab.waitFor(async () => (await tab.hud())?.findMode);
    await tab.type("need");
    await tab.waitFor(async () => (await tab.hud()).text.includes("(1 Match)"));
    await tab.evaluate(() => document.body.insertAdjacentHTML("beforeend", "<p>needle</p>"));
    await tab.type("l");
    await tab.waitFor(async () => (await tab.hud()).text.includes("(2 Matches)"));
  });

  should("keep the highlights after Enter, and clear them on a click", async ({ tab }) => {
    await tab.load(`<p>needle needle needle</p>`);
    const highlighted = () =>
      tab.evaluate(() => CSS.highlights.get("vimium-find-match")?.size ?? 0);
    await tab.keys("/");
    await tab.waitFor(async () => (await tab.hud())?.findMode);
    await tab.type("needle");
    await tab.waitFor(async () => (await highlighted()) == 2);
    await tab.keys("<enter>");
    await tab.keys("n");
    await tab.waitFor(() => tab.evaluate(() => getSelection().anchorOffset == 7));
    assert.equal(2, await highlighted());
    await tab.page.mouse.click(5, 5);
    await tab.waitFor(async () => (await highlighted()) == 0);
  });

  should("search backward with the reverse option", async ({ tab }) => {
    await tab.harness.setSettings({ keyMappings: "map ? enterFindMode reverse" });
    await tab.load(`
      <p id="a">needle</p>
      <p id="b">needle</p>
      <p id="start">start</p>
      <p id="c">needle</p>
    `);
    await tab.evaluate(() => {
      getSelection().collapse(document.getElementById("start").firstChild, 0);
    });
    const isSelected = (id) =>
      tab.evaluate((id) => getSelection().anchorNode?.parentElement.id == id, id);
    await tab.keys("?");
    await tab.waitFor(async () => (await tab.hud())?.findMode);
    assert.equal("?", (await tab.hud()).prompt);
    await tab.type("needle");
    await tab.waitFor(() => isSelected("b"));
    await tab.keys("<enter>");
    // n repeats in the search's direction, and N reverses it.
    await tab.keys("n");
    await tab.waitFor(() => isSelected("a"));
    await tab.keys("N");
    await tab.waitFor(() => isSelected("b"));
  });
});

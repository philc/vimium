import { assert, context, setup, should, teardown } from "../vendor/shoulda.js";
import * as e2e from "./harness.js";

const tallPage = `<div style="height: 5000px">Tall page</div>`;

context("normal mode", () => {
  setup(e2e.setup);
  teardown(e2e.teardown);

  should("use a custom key mapping from settings", async ({ tab }) => {
    await tab.harness.setSettings({ keyMappings: "map x scrollToBottom" });
    await tab.load(tallPage);
    await tab.keys("x");
    await tab.waitFor(() =>
      tab.evaluate(() => globalThis.scrollY + globalThis.innerHeight >= document.body.scrollHeight)
    );
  });

  should("ignore keys on a page matched by an exclusion rule", async ({ tab }) => {
    await tab.harness.setSettings({
      exclusionRules: [{ pattern: "http://localhost*", passKeys: "" }],
    });
    await tab.load(`<a href="/fixtures/link_destination.html">target</a>`);
    await tab.keys("f");
    assert.equal([], await tab.hintMarkers());
  });
});

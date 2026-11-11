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
});

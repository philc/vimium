import { context, setup, should, teardown } from "../vendor/shoulda.js";
import * as e2e from "./harness.js";

context("vomnibar", () => {
  setup(e2e.setup);
  teardown(e2e.teardown);

  should("navigate to a typed URL", async ({ tab }) => {
    await tab.load(`<p>page</p>`);
    await tab.keys("o");
    await tab.waitFor(() => tab.vomnibar());
    await tab.type(tab.serverUrl("/fixtures/link_destination.html"));
    await tab.keys("<enter>");
    await tab.waitFor(() => tab.path() == "/fixtures/link_destination.html");
  });

  // The Vomnibar's iframe loads on its first use in a page. Keys typed while it's loading should
  // still reach it, rather than going to the page.
  should("keep keys typed while the Vomnibar is loading", async ({ tab }) => {
    const searchUrl = tab.serverUrl("/fixtures/link_destination.html?q=%s");
    await tab.harness.setSettings({ searchEngines: `w: ${searchUrl} Search` });
    await tab.load(`<p>page</p>`);
    await tab.keys("o");
    await tab.type("w hello");
    await tab.waitFor(async () => (await tab.vomnibar())?.query == "hello");
    await tab.keys("<enter>");
    await tab.waitFor(() => tab.url().endsWith("/fixtures/link_destination.html?q=hello"));
  });
});

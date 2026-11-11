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
});

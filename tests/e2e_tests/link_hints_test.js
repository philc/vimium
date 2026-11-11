import { assert, context, setup, should, teardown } from "../vendor/shoulda.js";
import * as e2e from "./harness.js";

context("link hints", () => {
  setup(e2e.setup);
  teardown(e2e.teardown);

  should("follow a link in the current tab", async ({ tab }) => {
    await tab.load(`<a href="/fixtures/link_destination.html">target</a>`);
    await tab.keys("f");
    const markers = await tab.hintMarkers();
    assert.equal(1, markers.length);
    await tab.keys(markers[0]);
    await tab.waitFor(() => tab.path() == "/fixtures/link_destination.html");
  });

  should("open a link in a new tab", async ({ tab }) => {
    await tab.load(`<a href="/fixtures/link_destination.html">target</a>`);
    await tab.keys("F");
    const markers = await tab.hintMarkers();
    await tab.keys(markers[0]);
    await tab.waitFor(async () => {
      const urls = await tab.harness.tabUrls();
      return urls.length == 2 &&
        urls.some((url) => url.endsWith("/fixtures/link_destination.html"));
    }, { message: "a second tab with the target page" });
  });

  should("hint links inside a same-origin iframe", async ({ tab }) => {
    const frameSrc = tab.harness.server.addInlinePage(
      `<a href="/fixtures/link_destination.html" target="_top">in frame</a>`,
    );
    await tab.load(
      `<a href="/fixtures/link_destination.html">top</a><iframe src="${frameSrc}"></iframe>`,
    );
    await tab.keys("f");
    // One for each link, plus one for the frame's body, which lets the user focus the frame.
    assert.equal(3, (await tab.hintMarkers()).length);
  });

  should("hint links inside a cross-origin iframe", async ({ tab }) => {
    const frameSrc = tab.serverUrl(
      tab.harness.server.addInlinePage(
        `<a href="/fixtures/link_destination.html" target="_top">in frame</a>`,
      ),
      { crossOrigin: true },
    );
    await tab.load(
      `<a href="/fixtures/link_destination.html">top</a><iframe src="${frameSrc}"></iframe>`,
    );
    await tab.keys("f");
    // One for each link, plus one for the frame's body, which lets the user focus the frame.
    assert.equal(3, (await tab.hintMarkers()).length);
  });
});

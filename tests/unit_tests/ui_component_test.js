import * as testHelper from "./test_helper.js";
import "../../lib/utils.js";
import "../../lib/dom_utils.js";
import "../../lib/settings.js";
import "../../content_scripts/ui_component.js";

function stubPostMessage(iframeEl, fn) {
  if (!iframeEl || !fn) {
    throw new Error("iframeEl and fn are required.");
  }
  Object.defineProperty(iframeEl, "contentWindow", {
    value: { postMessage: fn },
    writable: false,
    configurable: true,
  });
}

context("UIComponent", () => {
  let c;

  setup(async () => {
    // Which page we load doesn't matter; we just need any DOM.
    await testHelper.jsdomStub("pages/help_dialog_page.html");
    stub(Utils, "isFirefox", () => false);
    await Settings.onLoaded();
  });

  teardown(() => {
    // MessageChannel ports must be closed, or our test process will never terminate. See
    // https://github.com/facebook/react/issues/26608
    for (const port of c?.messageChannelPorts) {
      port.close();
    }
  });

  should("focus the frame when showing", async () => {
    c = new UIComponent("testing.html", "example-class");
    await c.load("example.html", "example-class");
    stubPostMessage(c.iframeElement, function () {});
    // `window` here is the jsdom window stubbed onto globalThis by test_helper's jsdomStub, and
    // must be used to construct the Event so it belongs to the same realm as c.iframeElement;
    // globalThis.Event is a different (Deno-native) class and jsdom rejects it as "not of type
    // Event" when dispatched.
    // deno-lint-ignore no-window no-window-prefix
    c.iframeElement.dispatchEvent(new window.Event("load"));
    assert.equal(document.body, document.activeElement);

    // The shadow root element containing the iframe should be focused.
    c.show();
    assert.equal(c.iframeElement.getRootNode().host, document.activeElement);
  });
});

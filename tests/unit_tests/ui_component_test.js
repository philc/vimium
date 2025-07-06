import * as testHelper from "./test_helper.js";
import "../../lib/utils.js";
import "../../lib/dom_utils.js";
import "../../content_scripts/ui_component.js";

function stubPostMessage(iframeEl, fn) {
  if (!iframeEl || !fn) throw new Error("iframeEl and fn are required.");
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
    c.iframeElement.dispatchEvent(new window.Event("load"));
    assert.equal(document.body, document.activeElement);

    // The shadow root element containing the iframe should be focused.
    c.show();
    assert.equal(c.iframeElement.getRootNode().host, document.activeElement);
  });
});

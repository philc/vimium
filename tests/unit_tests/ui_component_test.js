import * as testHelper from "./test_helper.js";
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

// TODO(philc): We're effectively calling UIComponent.init() twice in these tests, because the
// constructor all calls init. I think we should change all call sites of new UIComponent() to then
// call init afterwards, and change its name to "load".
context("UIComponent", () => {
  setup(async () => {
    // Which page we load doesn't matter; we just need any DOM.
    await testHelper.jsdomStub("pages/help_dialog.html");
  });

  should("focus the frame when showing", async () => {
    const c = new UIComponent("testing.html", "example-class");
    await c.init("example.html", "example-class");
    stubPostMessage(c.iframeElement, function () {});
    c.iframeElement.dispatchEvent(new window.Event("load"));
    assert.equal(document.body, document.activeElement);

    // The shadow root element containing the iframe should be focused.
    c.activate();
    assert.equal(c.iframeElement.getRootNode().host, document.activeElement);
  });
});

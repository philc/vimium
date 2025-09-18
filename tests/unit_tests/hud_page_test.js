import * as testHelper from "./test_helper.js";
import "../../tests/unit_tests/test_chrome_stubs.js";
import * as hudPage from "../../pages/hud_page.js";
import * as UIComponentMessenger from "../../pages/ui_component_messenger.js";

function newKeyEvent(properties) {
  return Object.assign(
    {
      type: "keydown",
      key: "a",
      ctrlKey: false,
      shiftKey: false,
      altKey: false,
      metaKey: false,
      stopImmediatePropagation: function () {},
      preventDefault: function () {},
    },
    properties,
  );
}

context("hud page", () => {
  let ui;
  setup(async () => {
    stub(Utils, "isFirefox", () => false);
    await testHelper.jsdomStub("pages/hud_page.html");
    // Make Utils.setTimeout synchronous so that the tests easier to deal with.
    stub(Utils, "setTimeout", (timeout, fn) => {
      fn();
    });
  });

  teardown(() => {
    UIComponentMessenger.unregister();
  });

  should("find mode hides when escape is pressed", async () => {
    let message;
    const stubPort = {
      postMessage: (event) => {
        message = event;
      },
    };
    await UIComponentMessenger.registerPortWithOwnerPage({
      data: (await chrome.storage.session.get("vimiumSecret")).vimiumSecret,
      ports: [stubPort],
    });
    hudPage.handlers.showFindMode();
    await hudPage.onKeyEvent(newKeyEvent({ key: "Escape" }));
    assert.equal("hideFindMode", message.name);
  });
});

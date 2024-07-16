import "./test_helper.js";
import "../../lib/settings.js";
import "../../background_scripts/commands.js";
import "../../background_scripts/completion.js";
import "../../background_scripts/marks.js";
import "../../background_scripts/main.js";

context("HintCoordinator", () => {
  should("prepareToActivateLinKhintsMode", async () => {
    let receivedMessages = [];
    const frameIdToHintDescriptors = {
      "0": { frameId: 0, localIndex: 123, linkText: null },
      "1": { frameId: 1, localIndex: 456, linkText: null },
    };

    stub(chrome.webNavigation, "getAllFrames", () => [{ frameId: 0 }, { frameId: 1 }]);

    stub(chrome.tabs, "sendMessage", async (_tabId, message, options) => {
      if (message.messageType == "getHintDescriptors") {
        return frameIdToHintDescriptors[options.frameId];
      } else if (message.messageType == "activateMode") {
        receivedMessages.push(message);
      }
    });

    await HintCoordinator.prepareToActivateLinkHintsMode(0, 0, {
      modeIndex: 0,
      isVimiumHelpDialog: false,
    });

    receivedMessages = receivedMessages.map(
      (m) => Utils.pick(m, ["frameId", "frameIdToHintDescriptors"]),
    );

    // Each frame should receive only the hint descriptors from the other frames.
    assert.equal([
      { frameId: 0, frameIdToHintDescriptors: { "1": frameIdToHintDescriptors[1] } },
      { frameId: 1, frameIdToHintDescriptors: { "0": frameIdToHintDescriptors[0] } },
    ], receivedMessages);
  });
});

context("Next zoom level", () => {
  // NOTE: All these tests use the Chrome zoom levels, which are the default!
  should("Zoom in 0 times", async () => {
    const count = 0;
    const currentZoom = 1.00;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(1.00, nextZoom);
  });

  should("Zoom in 1", async () => {
    const count = 1;
    const currentZoom = 1.00;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(1.10, nextZoom);
  });

  should("Zoom out 1", async () => {
    const count = -1;
    const currentZoom = 1.00;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(0.90, nextZoom);
  });

  should("Zoom in 2", async () => {
    const count = 2;
    const currentZoom = 1.00;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(1.25, nextZoom);
  });

  should("Zoom out 2", async () => {
    const count = -2;
    const currentZoom = 1.00;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(0.80, nextZoom);
  });

  should("Zoom in from between values", async () => {
    const count = 1;
    const currentZoom = 1.05;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(1.10, nextZoom);
  });

  should("Zoom out from between values", async () => {
    const count = -1;
    const currentZoom = 1.05;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(1.00, nextZoom);
  });

  should("Zoom in past the maximum", async () => {
    const count = 15;
    const currentZoom = 1.00;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(5.00, nextZoom);
  });

  should("Zoom out past the minimum", async () => {
    const count = -15;
    const currentZoom = 1.00;
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(0.25, nextZoom);
  });

  should("Zoom in from below the minimum", async () => {
    const count = 1;
    const currentZoom = 0.01; // lowest non-broken Chrome zoom level
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(0.25, nextZoom);
  });

  should("Zoom out from above the maximum", async () => {
    const count = -1;
    const currentZoom = 9.99; // highest non-broken Chrome zoom level
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(5.00, nextZoom);
  });

  should("Zoom in from above the maximum", async () => {
    const count = 1;
    const currentZoom = 9.99; // highest non-broken Chrome zoom level
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(5.00, nextZoom);
  });

  should("Zoom out from below the minimum", async () => {
    const count = -1;
    const currentZoom = 0.01; // lowest non-broken Chrome zoom level
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(0.25, nextZoom);
  });

  should("Test Chrome 33% zoom in with float error", async () => {
    const count = 1;
    const currentZoom = 0.32999999999999996; // The value chrome actually gives for 33%.
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(0.50, nextZoom);
  });

  should("Test Chrome 175% zoom in with float error", async () => {
    const count = 1;
    const currentZoom = 1.7499999999999998; // The value chrome actually gives for 175%.
    const nextZoom = await nextZoomLevel(currentZoom, count);
    assert.equal(2.00, nextZoom);
  });
});

context("Selecting frames", () => {
  should("nextFrame", async () => {
    const focusedFrames = [];
    stub(chrome.webNavigation, "getAllFrames", () => [{ frameId: 1 }, { frameId: 2 }]);
    stub(chrome.tabs, "sendMessage", async (_tabId, message, options) => {
      if (message.handler == "getFocusStatus") {
        return { focused: options.frameId == 2, focusable: true };
      } else if (message.handler == "focusFrame") {
        focusedFrames.push(options.frameId);
      }
    });

    await BackgroundCommands.nextFrame(1, 0);
    assert.equal([1], focusedFrames);
  });
});

context("majorVersionHasIncreased", () => {
  should("return whether the major version has changed", () => {
    assert.equal(false, majorVersionHasIncreased(null));
    shoulda.stub(Utils, "getCurrentVersion", () => "2.0.1");
    assert.equal(false, majorVersionHasIncreased("2.0.0"));
    shoulda.stub(Utils, "getCurrentVersion", () => "2.1.0");
    assert.equal(true, majorVersionHasIncreased("2.0.0"));
  });
});

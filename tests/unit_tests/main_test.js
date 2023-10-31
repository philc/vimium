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

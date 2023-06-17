import "./test_helper.js";
import "../../background_scripts/completion.js";
import "../../background_scripts/marks.js";
import "../../background_scripts/main.js";

context("HintCoordinator", () => {
  should("prepareToActivateMode", async () => {
    let receivedMessages = [];
    const frameIdToHintDescriptors = {
      "0": { frameId: 0, localIndex: 123, linkText: null },
      "1": { frameId: 1, localIndex: 456, linkText: null },
    };

    stub(chrome.webNavigation, "getAllFrames", async () => [
      { frameId: 0 },
      { frameId: 1 },
    ]);

    stub(chrome.tabs, "sendMessage", async (tabId, message, options) => {
      if (message.messageType == "getHintDescriptors") {
        return frameIdToHintDescriptors[options.frameId];
      } else if (message.messageType == "activateMode") {
        receivedMessages.push(message);
      }
    });

    await HintCoordinator.prepareToActivateMode(0, 0, {
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

import "./test_helper.js";
import "../../background_scripts/completion.js";
import "../../background_scripts/marks.js";
import "../../background_scripts/main.js";

context("HintCoordinator", () => {
  should("prepareToActivateMode", async () => {
    let receivedMessages = [];
    const hintDescriptors = {
      "0": { frameId: 0, localIndex: 123, linkText: null },
      "1": { frameId: 1, localIndex: 456, linkText: null },
    };

    stub(chrome.webNavigation, "getAllFrames", async () => [
      { frameId: 0 },
      { frameId: 1 },
    ]);

    stub(chrome.tabs, "sendMessage", (tabId, message, options) => {
      if (message.messageType == "getHintDescriptors") {
        return hintDescriptors[options.frameId];
      } else if (message.messageType == "activateMode") {
        receivedMessages.push(message);
      }
    });

    await HintCoordinator.prepareToActivateMode(0, 0, {
      modeIndex: 0,
      isVimiumHelpDialog: false,
    });

    receivedMessages = receivedMessages.map((m) => Utils.pick(m, ["frameId", "hintDescriptors"]));

    // Each frame should receive only the hint descriptors from the other frames.
    assert.equal([
      { frameId: 0, hintDescriptors: { "1": hintDescriptors[1] } },
      { frameId: 1, hintDescriptors: { "0": hintDescriptors[0] } },
    ], receivedMessages);
  });
});

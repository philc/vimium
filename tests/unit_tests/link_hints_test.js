import "./test_helper.js";
import "../../lib/keyboard_utils.js";
import "../../lib/settings.js";
import "../../content_scripts/mode.js";
import "../../content_scripts/link_hints.js";

context("activateModeToOpenInNewWindow", () => {
  setup(async () => {
    await Settings.onLoaded();
  });

  teardown(async () => {
    await Settings.clear();
  });

  should("activate link hints with open-in-new-window mode", () => {
    let capturedMode = null;
    stub(LinkHints, "activateMode", (count, { mode }) => {
      capturedMode = mode;
    });
    LinkHints.activateModeToOpenInNewWindow(3);
    assert.equal("new-window", capturedMode.name);
    assert.equal("Open link in new window", capturedMode.indicator);
  });

  should("linkActivator sends openUrlInNewWindow for links with href", () => {
    let sentMessage = null;
    stub(chrome.runtime, "sendMessage", (msg) => {
      sentMessage = msg;
    });
    // Capture the mode object via the stub, then exercise its linkActivator.
    let capturedMode = null;
    stub(LinkHints, "activateMode", (_count, { mode }) => {
      capturedMode = mode;
    });
    LinkHints.activateModeToOpenInNewWindow(1);
    const mockLink = { href: "https://example.com" };
    capturedMode.linkActivator(mockLink);
    assert.equal("openUrlInNewWindow", sentMessage.handler);
    assert.equal("https://example.com", sentMessage.url);
  });
});

context("With insufficient link characters", () => {
  setup(async () => {
    await Settings.onLoaded();
  });

  teardown(async () => {
    await Settings.clear();
  });

  should("throw error in AlphabetHints", async () => {
    await Settings.set("linkHintCharacters", "ab");
    new AlphabetHints();
    await Settings.set("linkHintCharacters", "a");
    assert.throwsError(() => new AlphabetHints(), "Error");
  });

  should("throw error in FilterHints", async () => {
    await Settings.set("linkHintNumbers", "12");
    new FilterHints();
    await Settings.set("linkHintNumbers", "1");
    assert.throwsError(() => new FilterHints(), "Error");
  });
});

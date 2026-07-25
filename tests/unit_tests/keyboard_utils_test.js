import "./test_helper.js";
import "../../lib/settings.js";
import "../../lib/keyboard_utils.js";

context("KeyboardUtils", () => {
  setup(async () => {
    await Settings.load();
  });

  teardown(async () => {
    await chrome.storage.sync.clear();
    Settings._settings = null;
  });

  should("use event.code for IME composition events", () => {
    const keyChar = KeyboardUtils.getKeyChar({
      key: "ㄹ",
      code: "KeyF",
      isComposing: true,
      keyCode: 229,
    });
    assert.equal("f", keyChar);
  });

  should("use event.code for IME-style keydown events without isComposing", () => {
    const keyChar = KeyboardUtils.getKeyChar({
      key: "ㄹ",
      code: "KeyF",
      isComposing: false,
      keyCode: 229,
    });
    assert.equal("f", keyChar);
  });

  should("use event.code for non-Latin letters even without composition flags", () => {
    const keyChar = KeyboardUtils.getKeyChar({
      key: "ㄹ",
      code: "KeyF",
      isComposing: false,
      keyCode: 70,
    });
    assert.equal("f", keyChar);
  });

  should("preserve non-English Latin layouts outside IME composition", () => {
    const keyChar = KeyboardUtils.getKeyChar({
      key: "é",
      code: "Digit2",
      isComposing: false,
      keyCode: 50,
    });
    assert.equal("é", keyChar);
  });
});

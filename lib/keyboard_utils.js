let mapKeyRegistry = {};
Utils.monitorChromeStorage("mapKeyRegistry", value => { return mapKeyRegistry = value; });

const KeyboardUtils = {
  // This maps event.key key names to Vimium key names.
  keyNames: {
    "ArrowLeft": "left", "ArrowUp": "up", "ArrowRight": "right", "ArrowDown": "down", " ": "space"
  },

  init() {
    if (navigator.userAgent.indexOf("Mac") !== -1) {
      this.platform = "Mac";
    } else if (navigator.userAgent.indexOf("Linux") !== -1) {
      this.platform = "Linux";
    } else {
      this.platform = "Windows";
    }
  },

  getKeyChar(event) {
    let key;
    if (!Settings.get("ignoreKeyboardLayout")) {
      key = event.key;
    } else if (!event.code) {
      key = event.key != null ? event.key : ""; // Fall back to event.key (see #3099).
    } else if (event.code.slice(0, 6) === "Numpad") {
      // We cannot correctly emulate the numpad, so fall back to event.key; see #2626.
      key = event.key;
    } else {
      // The logic here is from the vim-like-key-notation project (https://github.com/lydell/vim-like-key-notation).
      key = event.code;
      if (key.slice(0, 3) === "Key") { key = key.slice(3); }
      // Translate some special keys to event.key-like strings and handle <Shift>.
      if (this.enUsTranslations[key]) {
        key = event.shiftKey ? this.enUsTranslations[key][1] : this.enUsTranslations[key][0];
      } else if ((key.length === 1) && !event.shiftKey) {
        key = key.toLowerCase();
      }
    }

    // It appears that key is not always defined (see #2453).
    if (!key) {
      return "";
    } else if (key in this.keyNames) {
      return this.keyNames[key];
    } else if (this.isModifier(event)) {
      return ""; // Don't resolve modifier keys.
    } else if (key.length === 1) {
      return key;
    } else {
      return key.toLowerCase();
    }
  },

  getKeyCharString(event) {
    let keyChar = this.getKeyChar(event);
    if (!keyChar)
      return;

    const modifiers = [];

    if (event.shiftKey && (keyChar.length === 1)) { keyChar = keyChar.toUpperCase(); }
    // These must be in alphabetical order (to match the sorted modifier order in Commands.normalizeKey).
    if (event.altKey) { modifiers.push("a"); }
    if (event.ctrlKey) { modifiers.push("c"); }
    if (event.metaKey) { modifiers.push("m"); }
    if (event.shiftKey && (keyChar.length > 1)) { modifiers.push("s"); }

    keyChar = [...modifiers, keyChar].join("-");
    if (1 < keyChar.length) { keyChar = `<${keyChar}>`; }
    keyChar = mapKeyRegistry[keyChar] != null ? mapKeyRegistry[keyChar] : keyChar;
    return keyChar;
  },

  isEscape: (function() {
    let useVimLikeEscape = true;
    Utils.monitorChromeStorage("useVimLikeEscape", value => useVimLikeEscape = value);

    return function(event) {
      // <c-[> is mapped to Escape in Vim by default.
      // Escape with a keyCode 229 means that this event comes from IME, and should not be treated as a
      // direct/normal Escape event.  IME will handle the event, not vimium.
      // See https://lists.w3.org/Archives/Public/www-dom/2010JulSep/att-0182/keyCode-spec.html
      return ((event.key === "Escape") && (event.keyCode !== 229)) ||
        (useVimLikeEscape && (this.getKeyCharString(event) === "<c-[>"));
    };
  })(),

  isBackspace(event) {
    return ["Backspace", "Delete"].includes(event.key);
  },

  isPrintable(event) {
    const s = this.getKeyCharString(event);
    return s && s.length == 1;
  },

  isModifier(event) {
    return ["Control", "Shift", "Alt", "OS", "AltGraph", "Meta"].includes(event.key);
  },

  enUsTranslations: {
    "Backquote":     ["`", "~"],
    "Minus":         ["-", "_"],
    "Equal":         ["=", "+"],
    "Backslash":     ["\\","|"],
    "IntlBackslash": ["\\","|"],
    "BracketLeft":   ["[", "{"],
    "BracketRight":  ["]", "}"],
    "Semicolon":     [";", ":"],
    "Quote":         ["'", '"'],
    "Comma":         [",", "<"],
    "Period":        [".", ">"],
    "Slash":         ["/", "?"],
    "Space":         [" ", " "],
    "Digit1":        ["1", "!"],
    "Digit2":        ["2", "@"],
    "Digit3":        ["3", "#"],
    "Digit4":        ["4", "$"],
    "Digit5":        ["5", "%"],
    "Digit6":        ["6", "^"],
    "Digit7":        ["7", "&"],
    "Digit8":        ["8", "*"],
    "Digit9":        ["9", "("],
    "Digit0":        ["0", ")"]
  }
};

KeyboardUtils.init();

global.KeyboardUtils = KeyboardUtils;

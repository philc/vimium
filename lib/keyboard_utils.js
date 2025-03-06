let mapKeyRegistry = {};
Utils.monitorChromeSessionStorage("mapKeyRegistry", (value) => {
  return mapKeyRegistry = value;
});

const KeyboardUtils = {
  // This maps event.key key names to Vimium key names.
  keyNames: {
    "ArrowLeft": "left",
    "ArrowUp": "up",
    "ArrowRight": "right",
    "ArrowDown": "down",
    " ": "space",
    "\n": "enter", // on a keypress event of Ctrl+Enter, tested on Chrome 92 and Windows 10
  },

  init() {
    // TODO(philc): Remove this guard clause once Deno has a userAgent.
    // https://github.com/denoland/deno/issues/14362
    // As of 2022-04-30, Deno does not have userAgent defined on navigator.
    if (navigator.userAgent == null) {
      this.platform = "Unknown";
      return;
    }
    if (navigator.userAgent.indexOf("Mac") !== -1) {
      this.platform = "Mac";
    } else if (navigator.userAgent.indexOf("Linux") !== -1) {
      this.platform = "Linux";
    } else {
      this.platform = "Windows";
    }
  },

  // Adds support for Mac Option + Keypress. See #3197.
  // (Vimium will ignore the symbols and treat them
  // like letters, at least on a US Laptop keyboard).
  // I only have a laptop with a US keyboard so I can only get the keypresses that are
  // available to me, and this list can likely be expanded. I have no idea if Option +
  // key in different regions produces different symbols or not.
  //
  // I suppose another way of handling this would be to simply treat any Option + (Shift? +)
  // key press as if "Ignore Keyboard Layout" and only use the event.code value for those
  // presses. If you'd rather implement it that way be my guest, I leave it up to you to
  // decide which approach is better/more efficient.
  macOptionSymbolMap: {
    "Backquote": { unshifted: { symbol: "Dead", key: "`" }, shifted: { symbol: "`", key: "~" } },
    "Digit1": { unshifted: { symbol: "¡", key: "1" }, shifted: { symbol: "⁄", key: "!" } },
    "Digit2": { unshifted: { symbol: "™", key: "2" }, shifted: { symbol: "€", key: "@" } },
    "Digit3": { unshifted: { symbol: "£", key: "3" }, shifted: { symbol: "‹", key: "#" } },
    "Digit4": { unshifted: { symbol: "¢", key: "4" }, shifted: { symbol: "›", key: "$" } },
    "Digit5": { unshifted: { symbol: "∞", key: "5" }, shifted: { symbol: "ﬁ", key: "%" } },
    "Digit6": { unshifted: { symbol: "§", key: "6" }, shifted: { symbol: "ﬂ", key: "^" } },
    "Digit7": { unshifted: { symbol: "¶", key: "7" }, shifted: { symbol: "‡", key: "&" } },
    "Digit8": { unshifted: { symbol: "•", key: "8" }, shifted: { symbol: "°", key: "*" } },
    "Digit9": { unshifted: { symbol: "ª", key: "9" }, shifted: { symbol: "·", key: "(" } },
    "Digit0": { unshifted: { symbol: "º", key: "0" }, shifted: { symbol: "‚", key: ")" } },
    "Minus": { unshifted: { symbol: "–", key: "-" }, shifted: { symbol: "—", key: "_" } },
    "Equal": { unshifted: { symbol: "≠", key: "=" }, shifted: { symbol: "±", key: "+" } },
    "KeyQ": { unshifted: { symbol: "œ", key: "q" }, shifted: { symbol: "Œ", key: "Q" } },
    "KeyW": { unshifted: { symbol: "∑", key: "w" }, shifted: { symbol: "„", key: "W" } },
    "KeyE": { unshifted: { symbol: "Dead", key: "e" }, shifted: { symbol: "´", key: "E" } },
    "KeyR": { unshifted: { symbol: "®", key: "r" }, shifted: { symbol: "‰", key: "R" } },
    "KeyT": { unshifted: { symbol: "†", key: "t" }, shifted: { symbol: "ˇ", key: "T" } },
    "KeyY": { unshifted: { symbol: "¥", key: "y" }, shifted: { symbol: "Á", key: "Y" } },
    "KeyU": { unshifted: { symbol: "Dead", key: "u" }, shifted: { symbol: "¨", key: "U" } },
    "KeyI": { unshifted: { symbol: "Dead", key: "i" }, shifted: { symbol: "ˆ", key: "I" } },
    "KeyO": { unshifted: { symbol: "ø", key: "o" }, shifted: { symbol: "Ø", key: "O" } },
    "KeyP": { unshifted: { symbol: "π", key: "p" }, shifted: { symbol: "∏", key: "P" } },
    "BracketLeft": { unshifted: { symbol: "“", key: "[" }, shifted: { symbol: "”", key: "{" } },
    "BracketRight": { unshifted: { symbol: "‘", key: "]" }, shifted: { symbol: "’", key: "}" } },
    "Backslash": { unshifted: { symbol: "«", key: "\\" }, shifted: { symbol: "»", key: "|" } },
    "KeyA": { unshifted: { symbol: "å", key: "a" }, shifted: { symbol: "Å", key: "A" } },
    "KeyS": { unshifted: { symbol: "ß", key: "s" }, shifted: { symbol: "Í", key: "S" } },
    "KeyD": { unshifted: { symbol: "∂", key: "d" }, shifted: { symbol: "Î", key: "D" } },
    "KeyF": { unshifted: { symbol: "ƒ", key: "f" }, shifted: { symbol: "Ï", key: "F" } },
    "KeyG": { unshifted: { symbol: "©", key: "g" }, shifted: { symbol: "˝", key: "G" } },
    "KeyH": { unshifted: { symbol: "˙", key: "h" }, shifted: { symbol: "Ó", key: "H" } },
    "KeyJ": { unshifted: { symbol: "∆", key: "j" }, shifted: { symbol: "Ô", key: "J" } },
    "KeyK": { unshifted: { symbol: "˚", key: "k" }, shifted: { symbol: "", key: "K" } },
    "KeyL": { unshifted: { symbol: "¬", key: "l" }, shifted: { symbol: "Ò", key: "L" } },
    "Semicolon": { unshifted: { symbol: "…", key: ";" }, shifted: { symbol: "Ú", key: ":" } },
    "Quote": { unshifted: { symbol: "æ", key: "'" }, shifted: { symbol: "Æ", key: "\"" } },
    "KeyZ": { unshifted: { symbol: "Ω", key: "z" }, shifted: { symbol: "¸", key: "Z" } },
    "KeyX": { unshifted: { symbol: "≈", key: "x" }, shifted: { symbol: "˛", key: "X" } },
    "KeyC": { unshifted: { symbol: "ç", key: "c" }, shifted: { symbol: "Ç", key: "C" } },
    "KeyV": { unshifted: { symbol: "√", key: "v" }, shifted: { symbol: "◊", key: "V" } },
    "KeyB": { unshifted: { symbol: "∫", key: "b" }, shifted: { symbol: "ı", key: "B" } },
    "KeyN": { unshifted: { symbol: "Dead", key: "n" }, shifted: { symbol: "˜", key: "N" } },
    "KeyM": { unshifted: { symbol: "µ", key: "m" }, shifted: { symbol: "Â", key: "M" } },
    "Comma": { unshifted: { symbol: "≤", key: "," }, shifted: { symbol: "¯", key: "<" } },
    "Period": { unshifted: { symbol: "≥", key: "." }, shifted: { symbol: "˘", key: ">" } },
    "Slash": { unshifted: { symbol: "÷", key: "/" }, shifted: { symbol: "¿", key: "?" } }
  },

  getKeyChar(event) {
    let key;
    if (!Settings.get("ignoreKeyboardLayout")) {
      if (this.platform !== 'Mac') key = event.key;
      if (!event.altKey) key = event.key;
      if (this.platform === 'Mac' && event.altKey) {
        if (this.macOptionSymbolMap[event.code] == null) key = event.key;
        else {
          const mapEntry = this.macOptionSymbolMap[event.code];
          const optionMap = event.shiftKey ? mapEntry.shifted : mapEntry.unshifted;

          if (event.key === optionMap.symbol || event.key === optionMap.key) {
            key = optionMap.key;
          }
        }
      }
    } else if (!event.code) {
      key = event.key != null ? event.key : ""; // Fall back to event.key (see #3099).
    } else if (event.code.slice(0, 6) === "Numpad") {
      // We cannot correctly emulate the numpad, so fall back to event.key; see #2626.
      key = event.key;
    } else {
      // The logic here is from the vim-like-key-notation project
      // (https://github.com/lydell/vim-like-key-notation).
      key = event.code;
      if (key.slice(0, 3) === "Key") key = key.slice(3);
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
    if (!keyChar) {
      return;
    }

    const modifiers = [];

    if (event.shiftKey && (keyChar.length === 1)) keyChar = keyChar.toUpperCase();
    // These must be in alphabetical order (to match the sorted modifier order in
    // Commands.normalizeKey).
    if (event.altKey) modifiers.push("a");
    if (event.ctrlKey) modifiers.push("c");
    if (event.metaKey) modifiers.push("m");
    if (event.shiftKey && (keyChar.length > 1)) modifiers.push("s");

    keyChar = [...modifiers, keyChar].join("-");
    if (1 < keyChar.length) keyChar = `<${keyChar}>`;
    keyChar = mapKeyRegistry[keyChar] != null ? mapKeyRegistry[keyChar] : keyChar;
    return keyChar;
  },

  isEscape: (function () {
    let useVimLikeEscape = true;
    Utils.monitorChromeSessionStorage("useVimLikeEscape", (value) => useVimLikeEscape = value);

    return function (event) {
      // <c-[> is mapped to Escape in Vim by default.
      // Escape with a keyCode 229 means that this event comes from IME, and should not be treated
      // as a direct/normal Escape event. IME will handle the event, not vimium.
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
    "Backquote": ["`", "~"],
    "Minus": ["-", "_"],
    "Equal": ["=", "+"],
    "Backslash": ["\\", "|"],
    "IntlBackslash": ["\\", "|"],
    "BracketLeft": ["[", "{"],
    "BracketRight": ["]", "}"],
    "Semicolon": [";", ":"],
    "Quote": ["'", '"'],
    "Comma": [",", "<"],
    "Period": [".", ">"],
    "Slash": ["/", "?"],
    "Space": [" ", " "],
    "Digit1": ["1", "!"],
    "Digit2": ["2", "@"],
    "Digit3": ["3", "#"],
    "Digit4": ["4", "$"],
    "Digit5": ["5", "%"],
    "Digit6": ["6", "^"],
    "Digit7": ["7", "&"],
    "Digit8": ["8", "*"],
    "Digit9": ["9", "("],
    "Digit0": ["0", ")"],
  },
};

KeyboardUtils.init();

globalThis.KeyboardUtils = KeyboardUtils;

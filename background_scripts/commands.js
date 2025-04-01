// A specification for a command that's currently bound to a key sequence, as defined by the default
// key bindings, or as it appears in the user's keymapping settings.
class RegistryEntry {
  // Array of keys.
  keySequence;
  // Name of the command.
  command;
  // Whether this command can be used with a count key prefix.
  noRepeat;
  // The maximum number of allow repetitions of this command, to avoid user error.
  repeatLimit;
  // Whether this command has to be run by the background page.
  background;
  // Whether this command must be run only in the top frame of a page.
  topFrame;
  // The map of options for this command. This is a parsed, sanitized version of the user's options
  // for this command.
  options;
  // The (optional) raw list of options for this command provided in the user's settings.
  // E.g. "count=10" in "map j scrollDown count=10".
  // NOTE(philc): This is used only by the createTab command.
  // TODO(philc): Can we remove this?
  optionList;

  constructor(o) {
    Object.seal(this);
    if (o) Object.assign(this, o);
  }
}

const Commands = {
  // A map of keyString => RegistryEntry
  keyToRegistryEntry: null,
  // A map of typed key => key it's mapped to (via the `mapkey` config statement).
  mapKeyRegistry: null,

  async init() {
    await Settings.onLoaded();
    Settings.addEventListener("change", async () => {
      await this.loadKeyMappings(Settings.get("keyMappings"));
    });
    await this.loadKeyMappings(Settings.get("keyMappings"));
  },

  // Parses the text supplied by the user in their "keyMappings" setting.
  // - shouldLogWarnings: if true, logs to the console when part of the user's config is invalid.
  // Returns { keyToRegistryEntry, keyToMappedKey, validationErrors }.
  parseKeyMappingsConfig(configText, shouldLogWarnings) {
    let keyToRegistryEntry = {};
    let mapKeyRegistry = {};
    const errors = [];
    const configLines = Utils.parseLines(configText);
    const commandsByName = Utils.keyBy(allCommands, "name");

    for (const line of configLines) {
      const tokens = line.split(/\s+/);
      const action = tokens[0].toLowerCase();
      switch (action) {
        case "map":
          if (tokens.length >= 3) {
            const [_, key, command, ...optionList] = tokens;
            const commandInfo = commandsByName[command];
            if (!commandInfo) {
              errors.push(`"${command}" is not a valid command in the line: ${line}`);
              continue;
            }
            const keySequence = this.parseKeySequence(key);
            const options = this.parseCommandOptions(command, optionList, commandInfo);
            keyToRegistryEntry[key] = new RegistryEntry({
              keySequence,
              command,
              noRepeat: commandInfo.noRepeat,
              repeatLimit: commandInfo.repeatLimit,
              background: commandInfo.background,
              topFrame: commandInfo.topFrame,
              options,
              optionList,
            });
          }
          break;
        case "unmap":
          if (tokens.length != 2) {
            errors.push(`Incorrect usage for unmap in the line: ${line}`);
            continue;
          }
          const key = tokens[1];
          delete keyToRegistryEntry[key];
          delete mapKeyRegistry[key];
          break;
        case "unmapall":
          keyToRegistryEntry = {};
          mapKeyRegistry = {};
          break;
        case "mapkey":
          if (tokens.length != 3) {
            errors.push(`Incorrect usage for mapKey in the line: ${line}`);
            continue;
          }
          const fromChar = this.parseKeySequence(tokens[1]);
          const toChar = this.parseKeySequence(tokens[2]);
          // NOTE(philc): I'm not sure why we enforce that the fromChar and toChar have to be
          // length one. It's been that way since this feature was introduced in 6596e30.
          const isValid = fromChar.length == toChar.length && toChar.length === 1;
          if (isValid) {
            mapKeyRegistry[fromChar[0]] = toChar[0];
          } else {
            errors.push(
              `mapkey only supports mapping keys which are single characters. Line: ${line}`,
            );
          }
          break;
        default:
          errors.push(`"${action}" is not a valid config command in line: ${line}`);
      }
    }

    return {
      keyToRegistryEntry,
      keyToMappedKey: mapKeyRegistry,
      validationErrors: errors,
    };
  },

  // Parses the user's keyMapping config text and persists the parsed key mappings into the
  // extension's storage, for use by the other parts of this extension.
  async loadKeyMappings(userKeyMappingsConfigText) {
    let key, command;
    this.keyToRegistryEntry = {};
    this.mapKeyRegistry = {};

    const defaultKeyConfig = Object.keys(defaultKeyMappings).map((key) =>
      `map ${key} ${defaultKeyMappings[key]}`
    ).join("\n");

    const parsed = this.parseKeyMappingsConfig(
      defaultKeyConfig + "\n" + userKeyMappingsConfigText,
      true,
    );
    this.mapKeyRegistry = parsed.keyToMappedKey;
    this.keyToRegistryEntry = parsed.keyToRegistryEntry;

    await chrome.storage.session.set({ mapKeyRegistry: this.mapKeyRegistry });
    await this.installKeyStateMapping();
    this.prepareHelpPageData();

    // Push the key mappings from any passNextKey commands into storage so that they're's available
    // to the front end so they can be detected during insert mode. We exclude single-key mappings
    // for this command (i.e. printable keys) because we're considering that a configuration error:
    // when users press printable keys in insert mode, they expect that character to be input, not
    // to be droppped into a special Vimium mode.
    const passNextKeys = Object.entries(this.keyToRegistryEntry)
      .filter(([key, v]) => v.command == "passNextKey" && key.length > 1)
      .map(([key, v]) => key);
    await chrome.storage.session.set({ passNextKeyKeys: passNextKeys });
  },

  // Lower-case the appropriate portions of named keys.
  //
  // A key name is one of three forms exemplified by <c-a> <left> or <c-f12> (prefixed normal key,
  // named key, or prefixed named key). Internally, for simplicity, we would like prefixes and key
  // names to be lowercase, though humans may prefer other forms <Left> or <C-a>.
  // On the other hand, <c-a> and <c-A> are different named keys - for one of them you have to press
  // "shift" as well.
  // We sort modifiers here to match the order used in keyboard_utils.js.
  // The return value is a sequence of keys: e.g. "<Space><c-A>b" -> ["<space>", "<c-A>", "b"].
  parseKeySequence: (function () {
    const modifier = "(?:[acms]-)"; // E.g. "a-", "c-", "m-", "s-".
    const namedKey = "(?:[a-z][a-z0-9]+)"; // E.g. "left" or "f12" (always two characters or more).
    const modifiedKey = `(?:${modifier}+(?:.|${namedKey}))`; // E.g. "c-*" or "c-left".
    const specialKeyRegexp = new RegExp(`^<(${namedKey}|${modifiedKey})>(.*)`, "i");
    return function (key) {
      if (key.length === 0) {
        return [];
        // Parse "<c-a>bcd" as "<c-a>" and "bcd".
      } else if (0 === key.search(specialKeyRegexp)) {
        const array = RegExp.$1.split("-");
        const adjustedLength = Math.max(array.length, 1);
        let modifiers = array.slice(0, adjustedLength - 1);
        let keyChar = array[adjustedLength - 1];
        if (keyChar.length !== 1) {
          keyChar = keyChar.toLowerCase();
        }
        modifiers = modifiers.map((m) => m.toLowerCase());
        modifiers.sort();
        return [
          "<" + modifiers.concat([keyChar]).join("-") + ">",
          ...this.parseKeySequence(RegExp.$2),
        ];
      } else {
        return [key[0], ...this.parseKeySequence(key.slice(1))];
      }
    };
  })(),

  // Command options follow command mappings, and are of one of two forms:
  //   key=value     - a value
  //   key           - a flag
  parseCommandOptions(command, optionList, commandInfo) {
    const options = {};
    for (const option of Array.from(optionList)) {
      const parse = option.split("=", 2);
      options[parse[0]] = parse.length === 1 ? true : parse[1];
    }

    // We parse any `count` option immediately (to avoid having to parse it repeatedly later).
    if ("count" in options) {
      options.count = parseInt(options.count);
      if (isNaN(options.count) || commandInfo.noRepeat) {
        delete options.count;
      }
    }

    return options;
  },

  // This generates and installs a nested key-to-command mapping structure. There is an example in
  // mode_key_handler.js.
  async installKeyStateMapping() {
    const keyStateMapping = {};
    for (const keys of Object.keys(this.keyToRegistryEntry || {})) {
      const registryEntry = this.keyToRegistryEntry[keys];
      let currentMapping = keyStateMapping;
      for (let index = 0; index < registryEntry.keySequence.length; index++) {
        const key = registryEntry.keySequence[index];
        if (currentMapping[key] != null ? currentMapping[key].command : undefined) {
          // Do not overwrite existing command bindings, they take priority. NOTE(smblott) This is
          // the legacy behaviour.
          break;
        } else if (index < (registryEntry.keySequence.length - 1)) {
          currentMapping = currentMapping[key] != null
            ? currentMapping[key]
            : (currentMapping[key] = {});
        } else {
          currentMapping[key] = Object.assign({}, registryEntry);
          // We don't need these properties in the content scripts.
          for (const prop of ["keySequence"]) {
            delete currentMapping[key][prop];
          }
        }
      }
    }
    await chrome.storage.session.set({
      normalModeKeyStateMapping: keyStateMapping,
      // Inform `KeyboardUtils.isEscape()` whether `<c-[>` should be interpreted as `Escape` (which it
      // is by default).
      useVimLikeEscape: !("<c-[>" in keyStateMapping),
    });
  },

  // Build the "helpPageData" data structure which the help page needs and place it in Chrome
  // storage.
  prepareHelpPageData() {
    /*
      Map of commands to option sets to keys to trigger that command option set.
      Commands with no options will have the empty string options set.
      Example:
      {
        "zoomReset": {
          "": ["z0", "zz"] // No options, with two key maps, ie: `map zz zoomReset`
        },
        "setZoom": {
          "1.1": ["z1"], // `map z1 setZoom 1.1`
          "1.2": ["z2"], // `map z2 setZoom 1.2`
        }
      }
    */
    // TODO(philc): Consider pulling this out into a different pure function.
    const commandToOptionsToKeys = {};
    for (const key of Object.keys(this.keyToRegistryEntry || {})) {
      const registryEntry = this.keyToRegistryEntry[key];
      const optionString = registryEntry.optionList?.join(" ") || "";
      commandToOptionsToKeys[registryEntry.command] ||= {};
      commandToOptionsToKeys[registryEntry.command][optionString] ||= [];
      commandToOptionsToKeys[registryEntry.command][optionString].push(key);
    }
    chrome.storage.session.set({ helpPageData: commandToOptionsToKeys });
  },

  // Rarely used commands are not shown by default in the help dialog or in the README. The goal is
  // to present a focused, high-signal set of commands to the new and casual user. Only those truly
  // hungry for more power from Vimium will uncover these gems.
  // TODO(philc): Remove/repurpose this data structure.
  advancedCommands: [
    "scrollToLeft",
    "scrollToRight",
    "moveTabToNewWindow",
    "findSelected",
    "findSelectedBackwards",
    "goUp",
    "goToRoot",
    "LinkHints.activateModeWithQueue",
    "LinkHints.activateModeToDownloadLink",
    "Vomnibar.activateEditUrl",
    "Vomnibar.activateEditUrlInNewTab",
    "LinkHints.activateModeToOpenIncognito",
    "LinkHints.activateModeToCopyLinkUrl",
    "goNext",
    "goPrevious",
    "Marks.activateCreateMode",
    "Marks.activateGotoMode",
    "moveTabLeft",
    "moveTabRight",
    "closeTabsOnLeft",
    "closeTabsOnRight",
    "closeOtherTabs",
    "enterVisualLineMode",
    "toggleViewSource",
    "passNextKey",
    "setZoom",
    "zoomIn",
    "zoomOut",
    "zoomReset",
    "reload hard",
  ],
};

const defaultKeyMappings = {
  // Navigating the current page
  "j": "scrollDown",
  "k": "scrollUp",
  "h": "scrollLeft",
  "l": "scrollRight",
  "gg": "scrollToTop",
  "G": "scrollToBottom",
  "zH": "scrollToLeft",
  "zL": "scrollToRight",
  "<c-e>": "scrollDown",
  "<c-y>": "scrollUp",
  "d": "scrollPageDown",
  "u": "scrollPageUp",
  "r": "reload",
  "R": "reload hard",
  "yy": "copyCurrentUrl",
  "p": "openCopiedUrlInCurrentTab",
  "P": "openCopiedUrlInNewTab",
  "gi": "focusInput",
  "[[": "goPrevious",
  "]]": "goNext",
  "gf": "nextFrame",
  "gF": "mainFrame",
  "gu": "goUp",
  "gU": "goToRoot",
  "i": "enterInsertMode",
  "v": "enterVisualMode",
  "V": "enterVisualLineMode",

  // Link hints
  "f": "LinkHints.activateMode",
  "F": "LinkHints.activateModeToOpenInNewTab",
  "<a-f>": "LinkHints.activateModeWithQueue",
  "yf": "LinkHints.activateModeToCopyLinkUrl",

  // Using find
  "/": "enterFindMode",
  "n": "performFind",
  "N": "performBackwardsFind",
  "*": "findSelected",
  "#": "findSelectedBackwards",

  // Vomnibar
  "o": "Vomnibar.activate",
  "O": "Vomnibar.activateInNewTab",
  "T": "Vomnibar.activateTabSelection",
  "b": "Vomnibar.activateBookmarks",
  "B": "Vomnibar.activateBookmarksInNewTab",
  "ge": "Vomnibar.activateEditUrl",
  "gE": "Vomnibar.activateEditUrlInNewTab",

  // Navigating history
  "H": "goBack",
  "L": "goForward",

  // Manipulating tabs
  "K": "nextTab",
  "J": "previousTab",
  "gt": "nextTab",
  "gT": "previousTab",
  "^": "visitPreviousTab",
  "<<": "moveTabLeft",
  ">>": "moveTabRight",
  "g0": "firstTab",
  "g$": "lastTab",
  "W": "moveTabToNewWindow",
  "t": "createTab",
  "yt": "duplicateTab",
  "x": "removeTab",
  "X": "restoreTab",
  "<a-p>": "togglePinTab",
  "<a-m>": "toggleMuteTab",
  "zi": "zoomIn",
  "zo": "zoomOut",
  "z0": "zoomReset",

  // Marks
  "m": "Marks.activateCreateMode",
  "`": "Marks.activateGotoMode",

  // Misc
  "?": "showHelp",
  "gs": "toggleViewSource",
};

globalThis.Commands = Commands;

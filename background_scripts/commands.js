import { allCommands } from "./all_commands.js";

// A specification for a command that's currently bound to a key sequence, as defined by the default
// key bindings, or as it appears in the user's keymapping settings.
class RegistryEntry {
  // Array of keys.
  keySequence;
  // Name of the command.
  command;
  // Whether this command can be used with a count key prefix.
  noRepeat;
  // The number of allowed repetitions of this command before the user is prompted for confirmation.
  repeatLimit;
  // Whether this command has to be run by the background page.
  background;
  // Whether this command must be run only in the top frame of a page.
  topFrame;
  // The map of options for this command. This is a parsed, sanitized version of the user's options
  // for this command.
  options;

  constructor(o) {
    Object.seal(this);
    if (o) Object.assign(this, o);
  }
}

// This is intentionally a superset of valid modifiers (a, c, m, s).
const modifier = "(?:[a-zA-Z]-)";
const namedKey = "(?:[a-z][a-z0-9]+)"; // E.g. "left" or "f12" (always two characters or more).
const modifiedKey = `(?:${modifier}+(?:.|${namedKey}))`; // E.g. "c-*" or "c-left".
const specialKeyRegexp = new RegExp(`^<(${namedKey}|${modifiedKey})>(.*)`, "i");

// Remove comments and leading/trailing whitespace from a list of lines, and merge lines where the
// last character on the preceding line is "\".
function parseLines(text) {
  return text.replace(/\\\n/g, "")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => (line.length > 0) && !(Array.from('#"').includes(line[0])));
}

// Returns the index of the nth occurrence of the regexp in the string. -1 if not found.
function nthRegexIndex(str, regex, n) {
  if (!regex.global) {
    regex = new RegExp(regex.source, regex.flags + "g");
  }
  let match;
  let count = 0;
  while ((match = regex.exec(str)) !== null) {
    count++;
    if (count === n) {
      return match.index;
    }
    // Prevent infinite loop for zero-length matches.
    if (match.index === regex.lastIndex) {
      regex.lastIndex++;
    }
  }
  return -1;
}

const KeyMappingsParser = {
  // Parses the text supplied by the user in their "keyMappings" setting.
  // - shouldLogWarnings: if true, logs to the console when part of the user's config is invalid.
  // Returns { keyToRegistryEntry, keyToMappedKey, validationErrors }.
  parse(configText, shouldLogWarnings) {
    let keyToRegistryEntry = {};
    let mapKeyRegistry = {};
    let errors = [];
    const configLines = parseLines(configText);
    const commandsByName = Utils.keyBy(allCommands, "name");

    const validModifiers = ["a", "c", "m", "s"];
    const validateParsedKey = function (key) {
      if (!key?.match(modifiedKey)) return;
      // Check that the modifier is valid and not capitalized.
      const mod = key.split("-")[0].slice(1);
      if (!validModifiers.includes(mod)) {
        return `${key} has an invalid modifier; valid modifiers are ${validModifiers}`;
      }
    };
    const validateUrl = function (str) {
      try {
        new URL(str);
        return true;
      } catch {
        return false;
      }
    };

    for (const line of configLines) {
      const tokens = line.split(/\s+/);
      const action = tokens[0].toLowerCase();
      switch (action) {
        case "map": {
          if (tokens.length < 3) {
            errors.push(`"map requires at least 2 arguments on line ${line}`);
            continue;
          }
          const [_, key, command] = tokens;
          let optionString;
          const optionsStart = nthRegexIndex(line, /\s+/, 3);
          if (optionsStart == -1) {
            optionString = "";
          } else {
            optionString = line.slice(optionsStart).trim();
          }
          const commandInfo = commandsByName[command];
          if (!commandInfo) {
            errors.push(`"${command}" is not a valid command in the line: ${line}`);
            continue;
          }
          const keySequence = this.parseKeySequence(key);
          const keyErrors = keySequence.map((k) => validateParsedKey(k)).filter((e) => e);
          if (keyErrors.length > 0) {
            errors = errors.concat(keyErrors);
            continue;
          }
          const options = this.parseCommandOptions(optionString);
          const allowedOptions = Object.keys(commandInfo.options || {});
          if (!commandInfo.noRepeat) {
            allowedOptions.push("count");
          }
          let hasUnknownOption = false;
          for (const option of Object.keys(options)) {
            if (allowedOptions.includes(option)) continue;
            if (allowedOptions.includes("(any url)")) {
              // Since this command allows for any URL as an argument, we perform some basic
              // validation to ensure the provided option string is indeed a URL.
              if (validateUrl(option)) continue;
              hasUnknownOption = true;
              errors.push(
                `Command ${command} does not support option ${option}. ` +
                  `Is this meant to be a valid URL?`,
              );
              break;
            } else {
              hasUnknownOption = true;
              errors.push(`Command ${command} does not support option ${option}`);
              break;
            }
          }
          if (hasUnknownOption) break;
          keyToRegistryEntry[key] = new RegistryEntry({
            keySequence,
            command,
            noRepeat: commandInfo.noRepeat,
            repeatLimit: commandInfo.repeatLimit,
            background: commandInfo.background,
            topFrame: commandInfo.topFrame,
            options,
          });
          break;
        }
        case "unmap": {
          if (tokens.length != 2) {
            errors.push(`Incorrect usage for unmap in the line: ${line}`);
            continue;
          }
          const key = tokens[1];
          delete keyToRegistryEntry[key];
          delete mapKeyRegistry[key];
          break;
        }
        case "unmapall": {
          keyToRegistryEntry = {};
          mapKeyRegistry = {};
          break;
        }
        case "mapkey": {
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
        }
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

  // Lower-case the appropriate portions of named keys.
  //
  // A key name is one of three forms exemplified by <c-a> <left> or <c-f12> (prefixed normal key,
  // named key, or prefixed named key). Internally, for simplicity, we would like prefixes and key
  // names to be lowercase, though humans may prefer other forms <Left> or <C-a>.
  // On the other hand, <c-a> and <c-A> are different named keys - for one of them you have to press
  // "shift" as well.
  // We sort modifiers here to match the order used in keyboard_utils.js.
  // The return value is a sequence of keys: e.g. "<Space><c-A>b" -> ["<space>", "<c-A>", "b"].
  parseKeySequence(key) {
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
  },

  // Command options follow command mappings, and are of one of these forms:
  //   key=value     - a value
  //   key="value"   - a value surrounded by quotes
  //   key           - a flag
  parseCommandOptions(optionString) {
    const options = {};
    while (optionString != "") {
      let match, matchedString, key, value;
      // Case: option value surrounded by quotes (key= "a b"). Spaces are allowed in the value.
      if (match = optionString.match(/^(\S+)="([^"]+)"(\s+|$)/)) {
        matchedString = match[0];
        key = match[1];
        value = match[2];
      } // Case: option value not surrounded by quotes (key=value). Spaces aren't allowed.
      else if (match = optionString.match(/^(\S+)=(\S+)(\s+|$)/)) {
        matchedString = match[0];
        key = match[1];
        value = match[2];
      } // Case: single option (flag).
      else if (match = optionString.match(/^([^\s=]+)(\s+|$)/)) {
        matchedString = match[0];
        key = match[1];
        value = true;
      }
      // NOTE(philc): If this string doesn't match any of our option regexps, we could throw an
      // error here or use an assert. I think this might only happen in the case where there's a
      // single equals sign. For now, just add the whole string as a flag option. If the command in
      // question doesn't accept this option, then an error will get surfaced to the user.
      if (match == null) {
        options[optionString] = true;
        break;
      }

      options[key] = value;
      optionString = optionString.slice(matchedString.length);
    }

    // We parse any `count` option immediately (to avoid having to parse it repeatedly later).
    if ("count" in options) {
      options.count = parseInt(options.count);
      if (isNaN(options.count)) {
        delete options.count;
      }
    }

    return options;
  },
};

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

  // Parses the user's keyMapping config text and persists the parsed key mappings into the
  // extension's storage, for use by the other parts of this extension.
  async loadKeyMappings(userKeyMappingsConfigText) {
    let key, command;
    this.keyToRegistryEntry = {};
    this.mapKeyRegistry = {};

    const defaultKeyConfig = Object.keys(defaultKeyMappings).map((key) =>
      `map ${key} ${defaultKeyMappings[key]}`
    ).join("\n");

    const parsed = KeyMappingsParser.parse(
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

  // Build the "commandToOptionsToKeys" data structure and place it in chrome's session storage.
  // This is used by the help page and commands listing.
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
    const commandToOptionsToKeys = {};
    const formatOptionString = (options) => {
      return Object.entries(options)
        .map(([k, v]) => {
          // When the value of an option is true, then it was parsed as a flag.
          if (v === true) {
            return k;
          } else {
            return `${k}=${v}`;
          }
        })
        .join(" ");
    };
    for (const key of Object.keys(this.keyToRegistryEntry || {})) {
      const registryEntry = this.keyToRegistryEntry[key];
      const optionString = formatOptionString(registryEntry.options || {});
      commandToOptionsToKeys[registryEntry.command] ||= {};
      commandToOptionsToKeys[registryEntry.command][optionString] ||= [];
      commandToOptionsToKeys[registryEntry.command][optionString].push(key);
    }
    chrome.storage.session.set({ commandToOptionsToKeys });
  },
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

export {
  Commands,
  // Exported for unit tests.
  defaultKeyMappings,
  KeyMappingsParser,
  parseLines,
};

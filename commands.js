var availableCommands    = {};
var keyToCommandRegistry = {};

/*
 * Registers a command, making it available to be optionally bound to a key.
 * options:
 *   - background: whether this command needs to be run against the background page.
 *   - passCountToFunction: true if this command should have any digits which were typed prior to the
 *     command passed to it. This is used to implement e.g. "closing of 3 tabs".
 */
function addCommand(command, description, options) {
  if (availableCommands[command]) {
    console.log(command, "is already defined! Check commands.js for duplicates.");
    return;
  }

  options = options || {};
  availableCommands[command] = { description: description,
                                 isBackgroundCommand: options.background,
                                 passCountToFunction: options.passCountToFunction
                               };
}

function mapKeyToCommand(key, command) {
  if (!availableCommands[command]) {
    console.log(command, "doesn't exist!");
    return;
  }

  keyToCommandRegistry[key] = { command: command,
                                isBackgroundCommand: availableCommands[command].isBackgroundCommand,
                                passCountToFunction: availableCommands[command].passCountToFunction
                              };
}

function unmapKey(key) { delete keyToCommandRegistry[key]; }

/* Lower-case the appropriate portions of named keys.
 *
 * A key name is one of three forms exemplified by <c-a> <left> or <c-f12>
 * (prefixed normal key, named key, or prefixed named key). Internally, for
 * simplicity, we would like prefixes and key names to be lowercase, though
 * humans may prefer other forms <Left> or <C-a>.
 * On the other hand, <c-a> and <c-A> are different named keys - for one of
 * them you have to press "shift" as well.
 */
function normalizeKey(key) {
    return key.replace(/<[acm]-/ig, function(match){ return match.toLowerCase(); })
              .replace(/<([acm]-)?([a-zA-Z0-9]{2,5})>/g, function(match, optionalPrefix, keyName){
                  return "<" + ( optionalPrefix ? optionalPrefix : "") + keyName.toLowerCase() + ">";
              });
}

function parseCustomKeyMappings(customKeyMappings) {
  lines = customKeyMappings.split("\n");

  for (var i = 0; i < lines.length; i++) {
    if (lines[i][0] == "\"" || lines[i][0] == "#") { continue }
    split_line = lines[i].split(/\s+/);

    var lineCommand = split_line[0];

    if (lineCommand == "map") {
      if (split_line.length != 3) { continue; }
      var key = normalizeKey(split_line[1]);
      var vimiumCommand = split_line[2];

      if (!availableCommands[vimiumCommand]) { continue }

      console.log("Mapping", key, "to", vimiumCommand);
      mapKeyToCommand(key, vimiumCommand);
    }
    else if (lineCommand == "unmap") {
      if (split_line.length != 2) { continue; }

      var key = normalizeKey(split_line[1]);

      console.log("Unmapping", key);
      unmapKey(key);
    }
    else if (lineCommand == "unmapAll") {
      keyToCommandRegistry = {};
    }
  }
}

function clearKeyMappingsAndSetDefaults() {
  keyToCommandRegistry = {};

  var defaultKeyMappings = {
    "?": "showHelp",
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
    "gs": "toggleViewSource",

    "i": "enterInsertMode",

    "H": "goBack",
    "L": "goForward",
    "gu": "goUp",

    "zi": "zoomIn",
    "zo": "zoomOut",
    "z0": "zoomReset",

    "gi": "focusInput",

    "f":     "activateLinkHintsMode",
    "F":     "activateLinkHintsModeToOpenInNewTab",
    "<a-f>": "activateLinkHintsModeWithQueue",

    "/": "enterFindMode",
    "n": "performFind",
    "N": "performBackwardsFind",

    "[[": "goPrevious",
    "]]": "goNext",

    "yy": "copyCurrentUrl",

    "K": "nextTab",
    "J": "previousTab",
    "gt": "nextTab",
    "gT": "previousTab",

    "t": "createTab",
    "x": "removeTab",
    "X": "restoreTab",

    "gf": "nextFrame"
  };

  for (var key in defaultKeyMappings)
    mapKeyToCommand(key, defaultKeyMappings[key]);
}

// This is a mapping of: commandIdentifier => [description, options].
var commandDescriptions = {
  // Navigating the current page
  showHelp: ["Show help", { background: true }],
  scrollDown: ["Scroll down"],
  scrollUp: ["Scroll up"],
  scrollLeft: ["Scroll left"],
  scrollRight: ["Scroll right"],
  scrollToTop: ["Scroll to the top of the page"],
  scrollToBottom: ["Scroll to the bottom of the page"],
  scrollToLeft: ["Scroll all the way to the left"],

  scrollToRight: ["Scroll all the way to the right"],
  scrollPageDown: ["Scroll a page down"],
  scrollPageUp: ["Scroll a page up"],
  scrollFullPageDown: ["Scroll a full page down"],
  scrollFullPageUp: ["Scroll a full page up"],

  reload: ["Reload the page"],
  toggleViewSource: ["View page source"],
  zoomIn: ["Zoom in"],
  zoomOut: ["Zoom out"],
  zoomReset: ["Reset zoom to default value"],
  copyCurrentUrl: ["Copy the current URL to the clipboard"],

  enterInsertMode: ["Enter insert mode"],

  focusInput: ["Focus the first (or n-th) text box on the page", { passCountToFunction: true }],

  activateLinkHintsMode: ["Open a link in the current tab"],
  activateLinkHintsModeToOpenInNewTab: ["Open a link in a new tab"],
  activateLinkHintsModeWithQueue: ["Open multiple links in a new tab"],

  enterFindMode: ["Enter find mode"],
  performFind: ["Cycle forward to the next find match"],
  performBackwardsFind: ["Cycle backward to the previous find match"],

  goPrevious: ["Follow the link labeled previous or <"],
  goNext: ["Follow the link labeled next or >"],

  // Navigating your history
  goBack: ["Go back in history"],
  goForward: ["Go forward in history"],

  // Navigating the URL hierarchy
  goUp: ["Go up the URL hierarchy", { passCountToFunction: true }],

  // Manipulating tabs
  nextTab: ["Go one tab right", { background: true }],
  previousTab: ["Go one tab left", { background: true }],
  createTab: ["Create new tab", { background: true }],
  removeTab: ["Close current tab", { background: true }],
  restoreTab: ["Restore closed tab", { background: true }],

  nextFrame: ["Cycle forward to the next frame on the page", { background: true }]
};

for (var command in commandDescriptions)
  addCommand(command, commandDescriptions[command][0], commandDescriptions[command][1]);


// An ordered listing of all available commands, grouped by type. This is the order they will
// be shown in the help page.
var commandGroups = {
  pageNavigation:
    ["scrollDown", "scrollUp", "scrollLeft", "scrollRight",
     "scrollToTop", "scrollToBottom", "scrollToLeft", "scrollToRight", "scrollPageDown",
     "scrollPageUp", "scrollFullPageUp", "scrollFullPageDown",
     "reload", "toggleViewSource", "zoomIn", "zoomOut", "zoomReset", "copyCurrentUrl", "goUp",
     "enterInsertMode", "focusInput",
     "activateLinkHintsMode", "activateLinkHintsModeToOpenInNewTab", "activateLinkHintsModeWithQueue",
     "goPrevious", "goNext", "nextFrame"],
  findCommands: ["enterFindMode", "performFind", "performBackwardsFind"],
  historyNavigation:
    ["goBack", "goForward"],
  tabManipulation:
    ["nextTab", "previousTab", "createTab", "removeTab", "restoreTab"],
  misc:
    ["showHelp"]
};

// Rarely used commands are not shown by default in the help dialog or in the README. The goal is to present
// a focused, high-signal set of commands to the new and casual user. Only those truly hungry for more power
// from Vimium will uncover these gems.
var advancedCommands = [
    "scrollToLeft", "scrollToRight",
    "zoomReset", "goUp", "focusInput", "activateLinkHintsModeWithQueue",
    "goPrevious", "goNext"];

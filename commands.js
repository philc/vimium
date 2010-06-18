var availableCommands    = {};
var keyToCommandRegistry = {};

function addCommand(command, description, isBackgroundCommand) {
  if (availableCommands[command])
  {
    console.log(command, "is already defined! Check commands.js for duplicates.");
    return;
  }

  availableCommands[command] = { description: description, isBackgroundCommand: isBackgroundCommand };
}

function mapKeyToCommand(key, command) {
  if (!availableCommands[command])
  {
    console.log(command, "doesn't exist!");
    return;
  }

  keyToCommandRegistry[key] = { command: command, isBackgroundCommand: availableCommands[command].isBackgroundCommand };
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

  mapKeyToCommand('?', 'showHelp');
  mapKeyToCommand('j', 'scrollDown');
  mapKeyToCommand('k', 'scrollUp');
  mapKeyToCommand('h', 'scrollLeft');
  mapKeyToCommand('l', 'scrollRight');
  mapKeyToCommand('gg', 'scrollToTop');
  mapKeyToCommand('G', 'scrollToBottom');
  mapKeyToCommand('<c-e>', 'scrollDown');
  mapKeyToCommand('<c-y>', 'scrollUp');
  mapKeyToCommand('<c-d>', 'scrollPageDown');
  mapKeyToCommand('<c-u>', 'scrollPageUp');
  mapKeyToCommand('<c-f>', 'scrollFullPageDown');
  mapKeyToCommand('<c-b>', 'scrollFullPageUp');
  mapKeyToCommand('r', 'reload');
  mapKeyToCommand('gf', 'toggleViewSource');

  mapKeyToCommand('i', 'enterInsertMode');

  mapKeyToCommand('H', 'goBack');
  mapKeyToCommand('L', 'goForward');
  mapKeyToCommand('gu', 'goUp');
  mapKeyToCommand('<c-a>', 'incrementUrl');
  mapKeyToCommand('<c-x>', 'decrementUrl');

  mapKeyToCommand('zi', 'zoomIn');
  mapKeyToCommand('zo', 'zoomOut');

  mapKeyToCommand('f', 'activateLinkHintsMode');
  mapKeyToCommand('F', 'activateLinkHintsModeToOpenInNewTab');

  mapKeyToCommand('/', 'enterFindMode');
  mapKeyToCommand('n', 'performFind');
  mapKeyToCommand('N', 'performBackwardsFind');

  mapKeyToCommand('yy', 'copyCurrentUrl');

  mapKeyToCommand('K', 'nextTab');
  mapKeyToCommand('J', 'previousTab');
  mapKeyToCommand('gt', 'nextTab');
  mapKeyToCommand('gT', 'previousTab');

  mapKeyToCommand('t', 'createTab');
  mapKeyToCommand('d', 'removeTab');
  mapKeyToCommand('u', 'restoreTab');
}

// Navigating the current page:
addCommand('showHelp',            'Show help',  true);
addCommand('scrollDown',          'Scroll down');
addCommand('scrollUp',            'Scroll up');
addCommand('scrollLeft',          'Scroll left');
addCommand('scrollRight',         'Scroll right');
addCommand('scrollToTop',         'Scroll to the top of the page');
addCommand('scrollToBottom',      'Scroll to the bottom of the page');
addCommand('scrollPageDown',      'Scroll a page down');
addCommand('scrollPageUp',        'Scroll a page up');
addCommand('scrollFullPageDown',  'Scroll a full page down');
addCommand('scrollFullPageUp',    'Scroll a full page up');

addCommand('reload',              'Reload the page');
addCommand('toggleViewSource',    'View page source');
addCommand('zoomIn',              'Zoom in');
addCommand('zoomOut',             'Zoom out');
addCommand('copyCurrentUrl',      'Copy the current URL to the clipboard');

addCommand('enterInsertMode',     'Enter insert mode');

addCommand('activateLinkHintsMode',               'Enter link hints mode to open links in current tab');
addCommand('activateLinkHintsModeToOpenInNewTab', 'Enter link hints mode to open links in new tab');

addCommand('enterFindMode',        'Enter find mode');
addCommand('performFind',          'Cycle forward to the next find match');
addCommand('performBackwardsFind', 'Cycle backward to the previous find match');

// Navigating your history:
addCommand('goBack',              'Go back in history');
addCommand('goForward',           'Go forward in history');

// Navigating the URL hierarchy
addCommand('goUp',                'Go up the URL hierarchy');
addCommand('incrementUrl',        'Increment the last number in the current URL');
addCommand('decrementUrl',        'Decrement the last number in the current URL');

// Manipulating tabs:
addCommand('nextTab',             'Go one tab right',  true);
addCommand('previousTab',         'Go one tab left',   true);
addCommand('createTab',           'Create new tab',    true);
addCommand('removeTab',           'Close current tab', true);
addCommand('restoreTab',          "Restore closed tab", true);


// An ordered listing of all available commands, grouped by type. This is the order they will
// be shown in the help page.
var commandGroups = {
  pageNavigation:
    ["scrollDown", "scrollUp", "scrollLeft", "scrollRight",
     "scrollToTop", "scrollToBottom", "scrollPageDown", "scrollPageUp", "scrollFullPageDown",
     "reload", "toggleViewSource", "zoomIn", "zoomOut", "copyCurrentUrl",
     "enterInsertMode", "activateLinkHintsMode", "activateLinkHintsModeToOpenInNewTab",
     "enterFindMode", "performFind", "performBackwardsFind"],
  historyNavigation:
    ["goBack", "goForward"],
  tabManipulation:
    ["nextTab", "previousTab", "createTab", "removeTab", "restoreTab"],
  misc:
    ["showHelp"]
};

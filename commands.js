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

function parseCustomKeyMappings(customKeyMappings) {
  lines = customKeyMappings.split("\n");

  for (var i = 0; i < lines.length; i++) {
    if (lines[i][0] == "\"" || lines[i][0] == "#") { continue }
    split_line = lines[i].split(" "); // TODO(ilya): Support all whitespace.
    if (split_line.length < 2) { continue }

    var lineCommand = split_line[0];
    var key         = split_line[1];

    if (lineCommand == "map") {
      if (split_line.length != 3) { continue }

      var vimiumCommand = split_line[2];

      if (!availableCommands[vimiumCommand]) { continue }

      console.log("Mapping", key, "to", vimiumCommand);
      mapKeyToCommand(key, vimiumCommand);
    }
    else if (lineCommand == "unmap") {
      console.log("Unmapping", key);
      unmapKey(key);
    }
  }
}

// TODO(ilya): Fill in these descriptions.
addCommand('scrollDown', '');
addCommand('scrollUp', '');
addCommand('scrollLeft', '');
addCommand('scrollRight', '');
addCommand('scrollToTop', '');
addCommand('scrollToBottom', '');
addCommand('scrollPageDown', '');
addCommand('scrollPageUp', '');
addCommand('scrollFullPageDown', '');
addCommand('scrollFullPageUp', '');
addCommand('reload', '');
addCommand('toggleViewSource', '');
addCommand('enterInsertMode', '');
addCommand('goBack', '');
addCommand('goForward', '');
addCommand('zoomIn', '');
addCommand('zoomOut', '');
addCommand('activateLinkHintsMode', '');
addCommand('activateLinkHintsModeToOpenInNewTab', '');
addCommand('enterFindMode', '');
addCommand('performFind', '');
addCommand('performBackwardsFind', '');
addCommand('copyCurrentUrl', '');
addCommand('nextTab', '', true);
addCommand('previousTab', '', true);
addCommand('createTab', '', true);
addCommand('removeTab', '', true);
addCommand('restoreTab', '', true);

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

mapKeyToCommand('ba', 'goBack');
mapKeyToCommand('H', 'goBack');
mapKeyToCommand('fw', 'goForward');
mapKeyToCommand('fo', 'goForward');
mapKeyToCommand('L', 'goForward');

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

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

function mapKeyToCommand(key, command)
{
  if (!availableCommands[command])
  {
    console.log(command, "doesn't exist!");
    return;
  }

  keyToCommandRegistry[key] = { command: command, isBackgroundCommand: availableCommands[command].isBackgroundCommand };
}

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
addCommand('goBack', '');
addCommand('goForward', '');
addCommand('goForward', '');
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

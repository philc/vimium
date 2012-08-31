var currentVersion = Utils.getCurrentVersion();

var tabQueue = {}; // windowId -> Array
var openTabs = {}; // tabId -> object with various tab properties
var keyQueue = ""; // Queue of keys typed
var validFirstKeys = {};
var singleKeyCommands = [];
var focusedFrame = null;
var framesForTab = {};

// Keys are either literal characters, or "named" - for example <a-b> (alt+b), <left> (left arrow) or <f12>
// This regular expression captures two groups: the first is a named key, the second is the remainder of
// the string.
var namedKeyRegex = /^(<(?:[amc]-.|(?:[amc]-)?[a-z0-9]{2,5})>)(.*)$/;

// Port handler mapping
var portHandlers = {
  keyDown:              handleKeyDown,
  settings:             handleSettings,
  filterCompleter:      filterCompleter
};

var sendRequestHandlers = {
  getCompletionKeys: getCompletionKeysRequest,
  getCurrentTabUrl: getCurrentTabUrl,
  getShowAdvancedCommands: getShowAdvancedCommands,
  openUrlInNewTab: openUrlInNewTab,
  openUrlInCurrentTab: openUrlInCurrentTab,
  openOptionsPageInNewTab: openOptionsPageInNewTab,
  registerFrame: registerFrame,
  frameFocused: handleFrameFocused,
  upgradeNotificationClosed: upgradeNotificationClosed,
  updateScrollPosition: handleUpdateScrollPosition,
  copyToClipboard: copyToClipboard,
  isEnabledForUrl: isEnabledForUrl,
  saveHelpDialogSettings: saveHelpDialogSettings,
  selectSpecificTab: selectSpecificTab,
  refreshCompleter: refreshCompleter
};

// Event handlers
var selectionChangedHandlers = [];
var tabLoadedHandlers = {}; // tabId -> function()

var completionSources = {
  bookmarks: new BookmarkCompleter(),
  history: new HistoryCompleter(),
  domains: new DomainCompleter(),
  tabs: new TabCompleter()
};

var completers = {
  omni: new MultiCompleter([
    completionSources.bookmarks,
    completionSources.history,
    completionSources.domains]),
  bookmarks: new MultiCompleter([completionSources.bookmarks]),
  tabs: new MultiCompleter([completionSources.tabs])
};

chrome.extension.onConnect.addListener(function(port, name) {
  var senderTabId = port.sender.tab ? port.sender.tab.id : null;
  // If this is a tab we've been waiting to open, execute any "tab loaded" handlers, e.g. to restore
  // the tab's scroll position. Wait until domReady before doing this; otherwise operations like restoring
  // the scroll position will not be possible.
  if (port.name === "domReady" && senderTabId !== null) {
    if (tabLoadedHandlers[senderTabId]) {
      var toCall = tabLoadedHandlers[senderTabId];
      // Delete first to be sure there's no circular events.
      delete tabLoadedHandlers[senderTabId];
      toCall.call();
    }

    // domReady is the appropriate time to show the "vimium has been upgraded" message.
    // TODO: This might be broken on pages with frames.
    if (shouldShowUpgradeMessage())
      chrome.tabs.sendRequest(senderTabId, { name: "showUpgradeNotification", version: currentVersion });
  }

  if (portHandlers[port.name])
    port.onMessage.addListener(portHandlers[port.name]);
});

chrome.extension.onRequest.addListener(function (request, sender, sendResponse) {
  var senderTabId = sender.tab ? sender.tab.id : null;
  if (sendRequestHandlers[request.handler])
    sendResponse(sendRequestHandlers[request.handler](request, sender));
  // Ensure the sendResponse callback is freed.
  return false;
});

/*
 * Used by the content scripts to get their full URL. This is needed for URLs like "view-source:http:// .."
 * because window.location doesn't know anything about the Chrome-specific "view-source:".
 */
function getCurrentTabUrl(request, sender) {
  return sender.tab.url;
}

/*
 * Checks the user's preferences in local storage to determine if Vimium is enabled for the given URL.
 */
function isEnabledForUrl(request) {
  // excludedUrls are stored as a series of URL expressions separated by newlines.
  var excludedUrls = Settings.get("excludedUrls").split("\n");
  var isEnabled = true;
  for (var i = 0; i < excludedUrls.length; i++) {
    // The user can add "*" to the URL which means ".*"
    var regexp = new RegExp("^" + excludedUrls[i].replace(/\*/g, ".*") + "$");
    if (request.url.match(regexp))
      isEnabled = false;
  }
  return { isEnabledForUrl: isEnabled };
}

/*
 * Called by the popup UI. Strips leading/trailing whitespace and ignores empty strings.
 */
function addExcludedUrl(url) {
  url = trim(url);
  if (url === "") { return; }

  var excludedUrls = Settings.get("excludedUrls");
  excludedUrls += "\n" + url;
  Settings.set("excludedUrls", excludedUrls);

  chrome.tabs.query({ windowId: chrome.windows.WINDOW_ID_CURRENT, active: true }, function(tabs) {
    updateActiveState(tabs[0].id);
  });
}

function getShowAdvancedCommands(request){
  return Settings.get("helpDialog_showAdvancedCommands");
}

function saveHelpDialogSettings(request) {
  Settings.set("helpDialog_showAdvancedCommands", request.showAdvancedCommands);
}

function showHelp(callback, frameId) {
  chrome.tabs.getSelected(null, function(tab) {
    chrome.tabs.sendRequest(tab.id,
      { name: "toggleHelpDialog", dialogHtml: helpDialogHtml(), frameId:frameId });
  });
}

/*
 * Retrieves the help dialog HTML template from a file, and populates it with the latest keybindings.
 */
function helpDialogHtml(showUnboundCommands, showCommandNames, customTitle) {
  var commandsToKey = {};
  for (var key in Commands.keyToCommandRegistry) {
    var command = Commands.keyToCommandRegistry[key].command;
    commandsToKey[command] = (commandsToKey[command] || []).concat(key);
  }
  var dialogHtml = fetchFileContents("help_dialog.html");
  for (var group in Commands.commandGroups)
    dialogHtml = dialogHtml.replace("{{" + group + "}}",
        helpDialogHtmlForCommandGroup(group, commandsToKey, Commands.availableCommands,
                                      showUnboundCommands, showCommandNames));
  dialogHtml = dialogHtml.replace("{{version}}", currentVersion);
  dialogHtml = dialogHtml.replace("{{title}}", customTitle || "Help");
  return dialogHtml;
}

/*
 * Generates HTML for a given set of commands. commandGroups are defined in commands.js
 */
function helpDialogHtmlForCommandGroup(group, commandsToKey, availableCommands,
                                       showUnboundCommands, showCommandNames) {
  var html = [];
  for (var i = 0; i < Commands.commandGroups[group].length; i++) {
    var command = Commands.commandGroups[group][i];
    bindings = (commandsToKey[command] || [""]).join(", ");
    if (showUnboundCommands || commandsToKey[command]) {
      html.push(
        "<tr class='vimiumReset " +
            (Commands.advancedCommands.indexOf(command) >= 0 ? "advanced" : "") + "'>",
        "<td class='vimiumReset'>", Utils.escapeHtml(bindings), "</td>",
        "<td class='vimiumReset'>:</td><td class='vimiumReset'>", availableCommands[command].description);

      if (showCommandNames)
        html.push("<span class='vimiumReset commandName'>(" + command + ")</span>");

      html.push("</td></tr>");
    }
  }
  return html.join("\n");
}

/*
 * Fetches the contents of a file bundled with this extension.
 */
function fetchFileContents(extensionFileName) {
  var req = new XMLHttpRequest();
  req.open("GET", chrome.extension.getURL(extensionFileName), false); // false => synchronous
  req.send();
  return req.responseText;
}

/**
 * Returns the keys that can complete a valid command given the current key queue.
 */
function getCompletionKeysRequest(request) {
  return { name: "refreshCompletionKeys",
           completionKeys: generateCompletionKeys(),
           validFirstKeys: validFirstKeys
         };
}

/*
  * Opens the url in the current tab.
  */
 function openUrlInCurrentTab(request) {
   chrome.tabs.getSelected(null, function(tab) {
     chrome.tabs.update(tab.id, { url: Utils.convertToUrl(request.url) });
   });
 }

/*
 * Opens request.url in new tab and switches to it if request.selected is true.
 */
function openUrlInNewTab(request) {
  chrome.tabs.getSelected(null, function(tab) {
    chrome.tabs.create({ url: Utils.convertToUrl(request.url), index: tab.index + 1, selected: true });
  });
}

function openCopiedUrlInCurrentTab(request) { openUrlInCurrentTab({ url: Clipboard.paste() }); }

function openCopiedUrlInNewTab(request) { openUrlInNewTab({ url: Clipboard.paste() }); }

/*
 * Called when the user has clicked the close icon on the "Vimium has been updated" message.
 * We should now dismiss that message in all tabs.
 */
function upgradeNotificationClosed(request) {
  Settings.set("previousVersion", currentVersion);
  sendRequestToAllTabs({ name: "hideUpgradeNotification" });
}

/*
 * Copies some data (request.data) to the clipboard.
 */
function copyToClipboard(request) {
  Clipboard.copy(request.data);
}

/**
  * Selects the tab with the ID specified in request.id
  */
function selectSpecificTab(request) {
  chrome.tabs.update(request.id, { selected: true });
}

/*
 * Used by the content scripts to get settings from the local storage.
 */
function handleSettings(args, port) {
  if (args.operation == "get") {
    var value = Settings.get(args.key);
    port.postMessage({ key: args.key, value: value });
  }
  else { // operation == "set"
    Settings.set(args.key, args.value);
  }
}

function refreshCompleter(request) {
  completers[request.name].refresh();
}

function filterCompleter(args, port) {
  var queryTerms = args.query === "" ? [] : args.query.split(" ");
  completers[args.name].filter(queryTerms, function(results) {
    port.postMessage({ id: args.id, results: results });
  });
}

/*
 * Used by everyone to get settings from local storage.
 */
function getSettingFromLocalStorage(setting) {
  if (localStorage[setting] !== "" && !localStorage[setting]) {
    return defaultSettings[setting];
  } else {
    return localStorage[setting];
  }
}

function getCurrentTimeInSeconds() { Math.floor((new Date()).getTime() / 1000); }

chrome.tabs.onSelectionChanged.addListener(function(tabId, selectionInfo) {
  if (selectionChangedHandlers.length > 0) { selectionChangedHandlers.pop().call(); }
});

function repeatFunction(func, totalCount, currentCount, frameId) {
  if (currentCount < totalCount)
    func(function() { repeatFunction(func, totalCount, currentCount + 1, frameId); }, frameId);
}

// Start action functions
function createTab(callback) {
  chrome.tabs.create({}, function(tab) { callback(); });
}

function nextTab(callback) { selectTab(callback, "next"); }
function previousTab(callback) { selectTab(callback, "previous"); }
function firstTab(callback) { selectTab(callback, "first"); }
function lastTab(callback) { selectTab(callback, "last"); }

/*
 * Selects a tab before or after the currently selected tab. Direction is either "next", "previous", "first" or "last".
 */
function selectTab(callback, direction) {
  chrome.tabs.getAllInWindow(null, function(tabs) {
    if (tabs.length <= 1)
      return;
    chrome.tabs.getSelected(null, function(currentTab) {
        switch (direction) {
          case "next":
            toSelect = tabs[(currentTab.index + 1 + tabs.length) % tabs.length];
            break;
          case "previous":
            toSelect = tabs[(currentTab.index - 1 + tabs.length) % tabs.length];
            break;
          case "first":
            toSelect = tabs[0];
            break;
          case "last":
            toSelect = tabs[tabs.length - 1];
            break;
        }
        selectionChangedHandlers.push(callback);
        chrome.tabs.update(toSelect.id, { selected: true });
    });
  });
}

function removeTab(callback) {
  chrome.tabs.getSelected(null, function(tab) {
    chrome.tabs.remove(tab.id);
    // We can't just call the callback here because we actually need to wait
    // for the selection to change to consider this action done.
    selectionChangedHandlers.push(callback);
  });
}

function updateOpenTabs(tab) {
  openTabs[tab.id] = { url: tab.url, positionIndex: tab.index, windowId: tab.windowId };
  // Frames are recreated on refresh
  delete framesForTab[tab.id];
}

/* Updates the browserAction icon to indicated whether Vimium is enabled or disabled on the current page.
 * Also disables Vimium if it is currently enabled but should be disabled according to the url blacklist.
 * This lets you disable Vimium on a page without needing to reload.
 *
 * Three situations are considered:
 * 1. Active tab is disabled -> disable icon
 * 2. Active tab is enabled and should be enabled -> enable icon
 * 3. Active tab is enabled but should be disabled -> disable icon and disable vimium
 */
function updateActiveState(tabId) {
  var enabledIcon = "icons/browser_action_enabled.png";
  var disabledIcon = "icons/browser_action_disabled.png";
  chrome.tabs.get(tabId, function(tab) {
    // Default to disabled state in case we can't connect to Vimium, primarily for the "New Tab" page.
    chrome.browserAction.setIcon({ path: disabledIcon });
    chrome.tabs.sendRequest(tabId, { name: "getActiveState" }, function(response) {
      var isCurrentlyEnabled = response !== undefined && response.enabled;
      var shouldBeEnabled = isEnabledForUrl({url: tab.url}).isEnabledForUrl;

      if (isCurrentlyEnabled) {
        if (shouldBeEnabled) {
          chrome.browserAction.setIcon({ path: enabledIcon });
        } else {
          chrome.browserAction.setIcon({ path: disabledIcon });
          chrome.tabs.sendRequest(tabId, { name: "disableVimium" });
        }
      } else {
        chrome.browserAction.setIcon({ path: disabledIcon });
      }
    });
  });
}

function handleUpdateScrollPosition(request, sender) {
  updateScrollPosition(sender.tab, request.scrollX, request.scrollY);
}

function updateScrollPosition(tab, scrollX, scrollY) {
  openTabs[tab.id].scrollX = scrollX;
  openTabs[tab.id].scrollY = scrollY;
}


chrome.tabs.onUpdated.addListener(function(tabId, changeInfo, tab) {
  if (changeInfo.status != "loading") { return; } // only do this once per URL change
  updateOpenTabs(tab);
  updateActiveState(tabId);
});

chrome.tabs.onAttached.addListener(function(tabId, attachedInfo) {
  // We should update all the tabs in the old window and the new window.
  if (openTabs[tabId]) {
    updatePositionsAndWindowsForAllTabsInWindow(openTabs[tabId].windowId);
  }
  updatePositionsAndWindowsForAllTabsInWindow(attachedInfo.newWindowId);
});

chrome.tabs.onMoved.addListener(function(tabId, moveInfo) {
  updatePositionsAndWindowsForAllTabsInWindow(moveInfo.windowId);
});

chrome.tabs.onRemoved.addListener(function(tabId) {
  var openTabInfo = openTabs[tabId];
  updatePositionsAndWindowsForAllTabsInWindow(openTabInfo.windowId);

  // If we restore chrome:// pages, they'll ignore Vimium keystrokes when they reappear.
  // Pretend they never existed and adjust tab indices accordingly.
  // Could possibly expand this into a blacklist in the future
  if (/^chrome[^:]*:\/\/.*/.test(openTabInfo.url)) {
    for (var i in tabQueue[openTabInfo.windowId]) {
      if (tabQueue[openTabInfo.windowId][i].positionIndex > openTabInfo.positionIndex)
        tabQueue[openTabInfo.windowId][i].positionIndex--;
    }
    return;
  }

  if (tabQueue[openTabInfo.windowId])
    tabQueue[openTabInfo.windowId].push(openTabInfo);
  else
    tabQueue[openTabInfo.windowId] = [openTabInfo];

  delete openTabs[tabId];
  delete framesForTab[tabId];
});

chrome.tabs.onActiveChanged.addListener(function(tabId, selectInfo) {
  updateActiveState(tabId);
});

chrome.windows.onRemoved.addListener(function(windowId) {
  delete tabQueue[windowId];
});

function restoreTab(callback) {
  // TODO(ilya): Should this be getLastFocused instead?
  chrome.windows.getCurrent(function(window) {
    if (tabQueue[window.id] && tabQueue[window.id].length > 0)
    {
      var tabQueueEntry = tabQueue[window.id].pop();

      // Clean out the tabQueue so we don't have unused windows laying about.
      if (tabQueue[window.id].length === 0)
        delete tabQueue[window.id];

      // We have to chain a few callbacks to set the appropriate scroll position. We can't just wait until the
      // tab is created because the content script is not available during the "loading" state. We need to
      // wait until that's over before we can call setScrollPosition.
      chrome.tabs.create({ url: tabQueueEntry.url, index: tabQueueEntry.positionIndex }, function(tab) {
        tabLoadedHandlers[tab.id] = function() {
          var scrollPort = chrome.tabs.sendRequest(tab.id, {
            name: "setScrollPosition",
            scrollX: tabQueueEntry.scrollX,
            scrollY: tabQueueEntry.scrollY
          });
        };
        callback();
      });
    }
  });
}
// End action functions

function updatePositionsAndWindowsForAllTabsInWindow(windowId) {
  chrome.tabs.getAllInWindow(windowId, function (tabs) {
    for (var i = 0; i < tabs.length; i++) {
      var tab = tabs[i];
      var openTabInfo = openTabs[tab.id];
      if (openTabInfo) {
        openTabInfo.positionIndex = tab.index;
        openTabInfo.windowId = tab.windowId;
      }
    }
  });
}

function splitKeyIntoFirstAndSecond(key) {
  if (key.search(namedKeyRegex) === 0)
      return { first: RegExp.$1, second: RegExp.$2 };
  else
    return { first: key[0], second: key.slice(1) };
}

function getActualKeyStrokeLength(key) {
  if (key.search(namedKeyRegex) === 0)
    return 1 + getActualKeyStrokeLength(RegExp.$2);
  else
    return key.length;
}

function populateValidFirstKeys() {
  for (var key in Commands.keyToCommandRegistry)
  {
    if (getActualKeyStrokeLength(key) == 2)
      validFirstKeys[splitKeyIntoFirstAndSecond(key).first] = true;
  }
}

function populateSingleKeyCommands() {
  for (var key in Commands.keyToCommandRegistry)
  {
    if (getActualKeyStrokeLength(key) == 1)
      singleKeyCommands.push(key);
  }
}

function refreshCompletionKeysAfterMappingSave() {
  validFirstKeys = {};
  singleKeyCommands = [];

  populateValidFirstKeys();
  populateSingleKeyCommands();

  sendRequestToAllTabs(getCompletionKeysRequest());
}

/*
 * Generates a list of keys that can complete a valid command given the current key queue or the one passed
 * in.
 */
function generateCompletionKeys(keysToCheck) {
  var splitHash = splitKeyQueue(keysToCheck || keyQueue);
  command = splitHash.command;
  count = splitHash.count;

  var completionKeys = singleKeyCommands.slice(0);

  if (getActualKeyStrokeLength(command) == 1)
  {
    for (var key in Commands.keyToCommandRegistry)
    {
      var splitKey = splitKeyIntoFirstAndSecond(key);
      if (splitKey.first == command)
       completionKeys.push(splitKey.second);
    }
  }

  return completionKeys;
}

function splitKeyQueue(queue) {
  var match = /([1-9][0-9]*)?(.*)/.exec(queue);
  var count = parseInt(match[1], 10);
  var command = match[2];

  return {count: count, command: command};
}

function handleKeyDown(request, port) {
  var key = request.keyChar;
  if (key == "<ESC>") {
    console.log("clearing keyQueue");
    keyQueue = "";
  }
  else {
    console.log("checking keyQueue: [", keyQueue + key, "]");
    keyQueue = checkKeyQueue(keyQueue + key, port.sender.tab.id, request.frameId);
    console.log("new KeyQueue: " + keyQueue);
  }
}

function checkKeyQueue(keysToCheck, tabId, frameId) {
  var refreshedCompletionKeys = false;
  var splitHash = splitKeyQueue(keysToCheck);
  command = splitHash.command;
  count = splitHash.count;

  if (command.length === 0) { return keysToCheck; }
  if (isNaN(count)) { count = 1; }

  if (Commands.keyToCommandRegistry[command]) {
    registryEntry = Commands.keyToCommandRegistry[command];

    if (!registryEntry.isBackgroundCommand) {
      chrome.tabs.sendRequest(tabId, {
        name: "executePageCommand",
        command: registryEntry.command,
        frameId: frameId,
        count: count,
        passCountToFunction: registryEntry.passCountToFunction,
        completionKeys: generateCompletionKeys("")
      });
      refreshedCompletionKeys = true;
    } else {
      if(registryEntry.passCountToFunction){
        this[registryEntry.command](count);
      } else {
        repeatFunction(this[registryEntry.command], count, 0, frameId);
      }
    }

    newKeyQueue = "";
  } else if (getActualKeyStrokeLength(command) > 1) {
    var splitKey = splitKeyIntoFirstAndSecond(command);

    // The second key might be a valid command by its self.
    if (Commands.keyToCommandRegistry[splitKey.second])
      newKeyQueue = checkKeyQueue(splitKey.second, tabId, frameId);
    else
      newKeyQueue = (validFirstKeys[splitKey.second] ? splitKey.second : "");
  } else {
    newKeyQueue = (validFirstKeys[command] ? count.toString() + command : "");
  }

  // If we haven't sent the completion keys piggybacked on executePageCommand,
  // send them by themselves.
  if (!refreshedCompletionKeys) {
    chrome.tabs.sendRequest(tabId, getCompletionKeysRequest(), null);
  }

  return newKeyQueue;
}

/*
 * Message all tabs. Args should be the arguments hash used by the Chrome sendRequest API.
 */
function sendRequestToAllTabs(args) {
  chrome.windows.getAll({ populate: true }, function(windows) {
    for (var i = 0; i < windows.length; i++)
      for (var j = 0; j < windows[i].tabs.length; j++)
        chrome.tabs.sendRequest(windows[i].tabs[j].id, args, null);
  });
}

// Compares two version strings (e.g. "1.1" and "1.5") and returns
// -1 if versionA is < versionB, 0 if they're equal, and 1 if versionA is > versionB.
function compareVersions(versionA, versionB) {
  versionA = versionA.split(".");
  versionB = versionB.split(".");
  for (var i = 0; i < Math.max(versionA.length, versionB.length); i++) {
    var a = parseInt(versionA[i] || 0, 10);
    var b = parseInt(versionB[i] || 0, 10);
    if (a < b) return -1;
    else if (a > b) return 1;
  }
  return 0;
}

/*
 * Returns true if the current extension version is greater than the previously recorded version in
 * localStorage, and false otherwise.
 */
function shouldShowUpgradeMessage() {
  // Avoid showing the upgrade notification when previousVersion is undefined, which is the case for new
  // installs.
  if (!Settings.get("previousVersion"))
    Settings.set("previousVersion", currentVersion);
  return compareVersions(currentVersion, Settings.get("previousVersion")) == 1;
}

function openOptionsPageInNewTab() {
  chrome.tabs.getSelected(null, function(tab) {
    chrome.tabs.create({ url: chrome.extension.getURL("options/options.html"), index: tab.index + 1 });
  });
}

function registerFrame(request, sender) {
  if (!framesForTab[sender.tab.id])
    framesForTab[sender.tab.id] = { frames: [] };

  if (request.is_top) {
    focusedFrame = request.frameId;
    framesForTab[sender.tab.id].total = request.total;
  }

  framesForTab[sender.tab.id].frames.push({ id: request.frameId, area: request.area });

  // We've seen all the frames. Time to focus the largest one.
  // NOTE: Disabled because it's buggy with iframes.
  // if (framesForTab[sender.tab.id].frames.length >= framesForTab[sender.tab.id].total)
  //  focusLargestFrame(sender.tab.id);
}

function focusLargestFrame(tabId) {
  var mainFrameId = null;
  var mainFrameArea = 0;

  for (var i = 0; i < framesForTab[tabId].frames.length; i++) {
    var currentFrame = framesForTab[tabId].frames[i];

    if (currentFrame.area > mainFrameArea) {
      mainFrameId = currentFrame.id;
      mainFrameArea = currentFrame.area;
    }
  }

  chrome.tabs.sendRequest(tabId, { name: "focusFrame", frameId: mainFrameId, highlight: false });
}

function handleFrameFocused(request, sender) {
  focusedFrame = request.frameId;
}

function nextFrame(count) {
  chrome.tabs.getSelected(null, function(tab) {
    var frames = framesForTab[tab.id].frames;
    var curr_index = getCurrFrameIndex(frames);

    // TODO: Skip the "top" frame (which doesn't actually have a <frame> tag),
    // since it exists only to contain the other frames.
    var new_index = (curr_index + count) % frames.length;

    chrome.tabs.sendRequest(tab.id, { name: "focusFrame", frameId: frames[new_index].id, highlight: true });
  });
}

function getCurrFrameIndex(frames) {
  var index;
  for (index=0; index < frames.length; index++) {
    if (frames[index].id == focusedFrame)
        break;
  }
  return index;
}

/*
 * Convenience function for trimming leading and trailing whitespace.
 */
function trim(str) {
  return str.replace(/^\s*/, "").replace(/\s*$/, "");
}

function init() {
  Commands.clearKeyMappingsAndSetDefaults();

  if (Settings.has("keyMappings"))
    Commands.parseCustomKeyMappings(Settings.get("keyMappings"));

  // In version 1.22, we changed the mapping for "d" and "u" to be scroll page down/up instead of close
  // and restore tab. For existing users, we want to preserve existing behavior for them by adding some
  // custom key mappings on their behalf.
  if (Settings.get("previousVersion") == "1.21") {
    var customKeyMappings = Settings.get("keyMappings") || "";
    if ((Commands.keyToCommandRegistry["d"] || {}).command == "scrollPageDown")
      customKeyMappings += "\nmap d removeTab";
    if ((Commands.keyToCommandRegistry["u"] || {}).command == "scrollPageUp")
      customKeyMappings += "\nmap u restoreTab";
    if (customKeyMappings !== "") {
      Settings.set("keyMappings", customKeyMappings);
      Commands.parseCustomKeyMappings(customKeyMappings);
    }
  }

  populateValidFirstKeys();
  populateSingleKeyCommands();
  if (shouldShowUpgradeMessage())
    sendRequestToAllTabs({ name: "showUpgradeNotification", version: currentVersion });

  // Ensure that openTabs is populated when Vimium is installed.
  chrome.windows.getAll({ populate: true }, function(windows) {
    for (var i in windows) {
      for (var j in windows[i].tabs) {
        var tab = windows[i].tabs[j];
        updateOpenTabs(tab);
        chrome.tabs.sendRequest(tab.id, { name: "getScrollPosition" }, function() {
            return function(response) {
                if (response === undefined)
                    return;
                updateScrollPosition(tab, response.scrollX, response.scrollY);
            };
        }());
      }
    }
  });
}
init();

/**
 * Convenience function for development use.
 */
function runTests() {
  open(chrome.extension.getURL('test_harnesses/automated.html'));
}

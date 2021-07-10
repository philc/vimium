// NOTE(philc): This file has many superfluous return statements in its functions, as a result of
// converting from coffeescript to es6. Many can be removed, but I didn't take the time to diligently
// track down precisely which return statements could be removed when I was doing the conversion.

let showUpgradeMessage;

// The browser may have tabs already open. We inject the content scripts immediately so that they work straight
// away.
chrome.runtime.onInstalled.addListener(function({ reason }) {
  // See https://developer.chrome.com/extensions/runtime#event-onInstalled
  if ([ "chrome_update", "shared_module_update" ].includes(reason)) { return; }
  if (Utils.isFirefox()) { return; }
  const manifest = chrome.runtime.getManifest();
  // Content scripts loaded on every page should be in the same group. We assume it is the first.
  const contentScripts = manifest.content_scripts[0];
  const jobs = [ [ chrome.tabs.executeScript, contentScripts.js ], [ chrome.tabs.insertCSS, contentScripts.css ] ];
  // Chrome complains if we don't evaluate chrome.runtime.lastError on errors (and we get errors for tabs on
  // which Vimium cannot run).
  const checkLastRuntimeError = () => chrome.runtime.lastError;
  return chrome.tabs.query({ status: "complete" }, function(tabs) {
    for (let tab of tabs)
      for (let [ func, files ] of jobs)
        for (let file of files)
          func(tab.id, { file, allFrames: contentScripts.all_frames }, checkLastRuntimeError);
  });
});

const frameIdsForTab = {};
global.portsForTab = {};
global.urlForTab = {};

// This is exported for use by "marks.js".
global.tabLoadedHandlers = {}; // tabId -> function()

// A secret, available only within the current instantiation of Vimium, for the duration of the browser
// session. The secret is a generated strong random string.
const randomArray = window.crypto.getRandomValues(new Uint8Array(32)); // 32-byte random token.
const secretToken =  randomArray.reduce((a,b) => a.toString(16) + b.toString(16));
chrome.storage.local.set({vimiumSecret: secretToken});

const completionSources = {
  bookmarks: new BookmarkCompleter,
  history: new HistoryCompleter,
  domains: new DomainCompleter,
  tabs: new TabCompleter,
  searchEngines: new SearchEngineCompleter
};

const completers = {
  omni: new MultiCompleter([
    completionSources.bookmarks,
    completionSources.history,
    completionSources.domains,
    completionSources.tabs,
    completionSources.searchEngines
    ]),
  bookmarks: new MultiCompleter([completionSources.bookmarks]),
  tabs: new MultiCompleter([completionSources.tabs])
};

const completionHandlers = {
  filter(completer, request, port) {
    // TODO(philc): Do we need any of these return statements?
    return completer.filter(request, function(response) {
      // NOTE(smblott): response contains `relevancyFunction` (function) properties which cause postMessage,
      // below, to fail in Firefox. See #2576.  We cannot simply delete these methods, as they're needed
      // elsewhere.  Converting the response to JSON and back is a quick and easy way to sanitize the object.
      response = JSON.parse(JSON.stringify(response));
      // We use try here because this may fail if the sender has already navigated away from the original page.
      // This can happen, for example, when posting completion suggestions from the SearchEngineCompleter
      // (which is done asynchronously).
      try {
        return port.postMessage(Object.assign(request, response, {handler: "completions"}));
      } catch (error) {}
    });
  },

  refresh(completer, _, port) { completer.refresh(port); },
  cancel(completer, _, port) { completer.cancel(port); }
};

const handleCompletions = sender => (request, port) =>
      completionHandlers[request.handler](completers[request.name], request, port);

chrome.runtime.onConnect.addListener(function(port) {
  if (portHandlers[port.name])
    return port.onMessage.addListener(portHandlers[port.name](port.sender, port));
});

chrome.runtime.onMessage.addListener(function(request, sender, sendResponse) {
  request = Object.assign({count: 1, frameId: sender.frameId},
                          request,
                          {tab: sender.tab, tabId: sender.tab.id});
  if (sendRequestHandlers[request.handler]) {
    sendResponse(sendRequestHandlers[request.handler](request, sender));
  }
  // Ensure that the sendResponse callback is freed.
  return false;
});

const onURLChange = details => chrome.tabs.sendMessage(details.tabId, {name: "checkEnabledAfterURLChange"});

// Re-check whether Vimium is enabled for a frame when the url changes without a reload.
chrome.webNavigation.onHistoryStateUpdated.addListener(onURLChange); // history.pushState.
chrome.webNavigation.onReferenceFragmentUpdated.addListener(onURLChange); // Hash changed.

// Cache "content_scripts/vimium.css" in chrome.storage.local for UI components.
(function() {
  const req = new XMLHttpRequest();
  req.open("GET", chrome.runtime.getURL("content_scripts/vimium.css"), true); // true -> asynchronous.
  req.onload = function() {
    const {status, responseText} = req;
    if (status === 200)
      return chrome.storage.local.set({vimiumCSSInChromeStorage: responseText});
  };
  return req.send();
})();

const TabOperations = {
  // Opens the url in the current tab.
  openUrlInCurrentTab(request) {
    if (Utils.hasJavascriptPrefix(request.url)) {
      const tabId = request.tabId;
      const frameId = request.frameId;
      chrome.tabs.sendMessage(tabId, {frameId, name: "executeScript", script: request.url});
    } else {
      chrome.tabs.update(request.tabId, {url: Utils.convertToUrl(request.url)});
    }
  },

  // Opens request.url in new tab and switches to it.
  openUrlInNewTab(request, callback) {
    if (callback == null)
      callback = function() {};
    const tabConfig = {
      url: Utils.convertToUrl(request.url),
      active: true,
      windowId: request.tab.windowId
    };

    const position = request.position;

    let tabIndex = null;

    // TODO(philc): Convert to a switch statement ES6.
    switch (position) {
      case "start": tabIndex = 0; break;
      case "before": tabIndex = request.tab.index; break;
      // if on Chrome or on Firefox but without openerTabId, `tabs.create` opens a tab at the end.
      // but on Firefox and with openerTabId, it opens a new tab next to the opener tab
      case "end": tabIndex = (Utils.isFirefox() ? 9999 : null); break;
      // "after" is the default case when there are no options.
      default: tabIndex = request.tab.index + 1;
    }
    tabConfig.index = tabIndex;

    if (request.active != null)
      tabConfig.active = request.active;
    // Firefox does not support "about:newtab" in chrome.tabs.create.
    if (tabConfig["url"] === Settings.defaults.newTabUrl)
      delete tabConfig["url"];

    // Firefox <57 throws an error when openerTabId is used (issue 1238314).
    const canUseOpenerTabId = !(Utils.isFirefox() && (Utils.compareVersions(Utils.firefoxVersion(), "57") < 0));
    if (canUseOpenerTabId)
      tabConfig.openerTabId = request.tab.id;

    // clean position and active, so following `openUrlInNewTab(request)` will create a tab just next to this new tab
    return chrome.tabs.create(tabConfig, tab =>
      callback(Object.assign(request, {tab, tabId: tab.id, position: "", active: false})));
  },

  // Opens request.url in new window and switches to it.
  openUrlInNewWindow(request, callback) {
    if (callback == null)
      callback = function() {};
    const winConfig = {
      url: Utils.convertToUrl(request.url),
      active: true
    };
    if (request.active != null)
      winConfig.active = request.active;
    // Firefox does not support "about:newtab" in chrome.tabs.create.
    if (winConfig["url"] === Settings.defaults.newTabUrl)
      delete winConfig["url"];
    return chrome.windows.create(winConfig, callback);
  }
};

const muteTab = tab => chrome.tabs.update(tab.id, {muted: !tab.mutedInfo.muted});
const toggleMuteTab = function({tab: currentTab, registryEntry, tabId, frameId}) {
  if ((registryEntry.options.all != null) || (registryEntry.options.other != null)) {
    // If there are any audible, unmuted tabs, then we mute them; otherwise we unmute any muted tabs.
    chrome.tabs.query({audible: true}, function(tabs) {
      let tab;
      if (registryEntry.options.other != null)
        tabs = tabs.filter(t => t.id !== currentTab.id);
      const audibleUnmutedTabs = tabs.filter(t => t.audible && !t.mutedInfo.muted);
      if (audibleUnmutedTabs.length >= 0) {
        chrome.tabs.sendMessage(tabId, {frameId, name: "showMessage", message: `Muting ${audibleUnmutedTabs.length} tab(s).`});
        for (tab of audibleUnmutedTabs)
          muteTab(tab);
      } else {
        chrome.tabs.sendMessage(tabId, {frameId, name: "showMessage", message: "Unmuting all muted tabs."});
        for (tab of tabs)
          if (tab.mutedInfo.muted)
            muteTab(tab);
      }
    });
  } else {
    if (currentTab.mutedInfo.muted)
      chrome.tabs.sendMessage(tabId, {frameId, name: "showMessage", message: "Unmuted tab."});
    else
      chrome.tabs.sendMessage(tabId, {frameId, name: "showMessage", message: "Muted tab."});
    muteTab(currentTab);
  }
};

//
// Selects the tab with the ID specified in request.id
//
const selectSpecificTab = request => chrome.tabs.get(request.id, function(tab) {
  if (chrome.windows != null)
    chrome.windows.update(tab.windowId, { focused: true });
  return chrome.tabs.update(request.id, { active: true });
});

const moveTab = function({count, tab, registryEntry}) {
  if (registryEntry.command === "moveTabLeft")
    count = -count;
  return chrome.tabs.query({ currentWindow: true }, function(tabs) {
    const pinnedCount = (tabs.filter(tab => tab.pinned)).length;
    const minIndex = tab.pinned ? 0 : pinnedCount;
    const maxIndex = (tab.pinned ? pinnedCount : tabs.length) - 1;
    return chrome.tabs.move(tab.id,
      {index: Math.max(minIndex, Math.min(maxIndex, tab.index + count))});
  });
};

var mkRepeatCommand = command => (function(request) {
  request.count--;
  if (request.count >= 0)
    return command(request, request => (mkRepeatCommand(command))(request));
});

// These are commands which are bound to keystrokes which must be handled by the background page. They are
// mapped in commands.coffee.
const BackgroundCommands = {
  // Create a new tab.  Also, with:
  //     map X createTab http://www.bbc.com/news
  // create a new tab with the given URL.
  createTab: mkRepeatCommand(function(request, callback) {
    if (request.urls == null) {
      if (request.url) {
        // If the request contains a URL, then use it.
        request.urls = [request.url];
      } else {
        // Otherwise, if we have a registryEntry containing URLs, then use them.
        const urlList = request.registryEntry.optionList.filter(opt => Utils.isUrl(opt));
        if (urlList.length > 0) {
          request.urls = urlList;
        } else {
          // Otherwise, just create a new tab.
          const newTabUrl = Settings.get("newTabUrl");
          if (newTabUrl === "pages/blank.html") {
            // "pages/blank.html" does not work in incognito mode, so fall back to "chrome://newtab" instead.
            request.urls = [request.tab.incognito ? "chrome://newtab" : chrome.runtime.getURL(newTabUrl)];
          } else {
            request.urls = [newTabUrl];
          }
        }
      }
    }

    if (request.registryEntry.options.incognito || request.registryEntry.options.window) {
      const windowConfig = {
        url: request.urls,
        incognito: request.registryEntry.options.incognito || false
      };
      return chrome.windows.create(windowConfig, () => callback(request));
    } else {
      let openNextUrl;
      const urls = request.urls.slice().reverse();
      if (request.position == null)
        request.position = request.registryEntry.options.position;
      return (openNextUrl = function(request) {
        if (urls.length > 0)
          return TabOperations.openUrlInNewTab((Object.assign(request, {url: urls.pop()})), openNextUrl);
        else
          return callback(request);
      })(request);
    }
  }),

  duplicateTab: mkRepeatCommand((request, callback) => {
    return chrome.tabs.duplicate(request.tabId,
                                 tab => callback(Object.assign(request, {tab, tabId: tab.id})))
  }),

  moveTabToNewWindow({count, tab}) {
    chrome.tabs.query({currentWindow: true}, function(tabs) {
      const activeTabIndex = tab.index;
      const startTabIndex = Math.max(0, Math.min(activeTabIndex, tabs.length - count));
      [ tab, ...tabs ] = tabs.slice(startTabIndex, startTabIndex + count);
      chrome.windows.create({tabId: tab.id, incognito: tab.incognito}, function(window) {
        chrome.tabs.move(tabs.map(t => t.id), {windowId: window.id, index: -1});
      });
    });
  },

  nextTab(request) { return selectTab("next", request); },
  previousTab(request) { return selectTab("previous", request); },
  firstTab(request) { return selectTab("first", request); },
  lastTab(request) { return selectTab("last", request); },
  removeTab({count, tab}) { return forCountTabs(count, tab, tab => chrome.tabs.remove(tab.id)); },
  restoreTab: mkRepeatCommand((request, callback) => chrome.sessions.restore(null, callback(request))),
  togglePinTab({count, tab}) { return forCountTabs(count, tab, tab => chrome.tabs.update(tab.id, {pinned: !tab.pinned})); },
  toggleMuteTab,
  moveTabLeft: moveTab,
  moveTabRight: moveTab,

  nextFrame({count, frameId, tabId}) {
    frameIdsForTab[tabId] = cycleToFrame(frameIdsForTab[tabId], frameId, count);
    return chrome.tabs.sendMessage(tabId, {name: "focusFrame", frameId: frameIdsForTab[tabId][0], highlight: true});
  },

  closeTabsOnLeft(request) { return removeTabsRelative("before", request); },
  closeTabsOnRight(request) { return removeTabsRelative("after", request); },
  closeOtherTabs(request) { return removeTabsRelative("both", request); },

  visitPreviousTab({count, tab}) {
    const tabIds = BgUtils.tabRecency.getTabsByRecency().filter(tabId => tabId !== tab.id);
    if (tabIds.length > 0)
      return selectSpecificTab({id: tabIds[(count-1) % tabIds.length]});
  },

  reload({count, tabId, registryEntry, tab: {windowId}}){
    const bypassCache = registryEntry.options.hard != null ? registryEntry.options.hard : false;
    return chrome.tabs.query({windowId}, function(tabs) {
      const position = (function() {
        for (let index = 0; index < tabs.length; index++) {
          const tab = tabs[index];
          if (tab.id === tabId) { return index; }
        }
      })();
      tabs = [...tabs.slice(position), ...tabs.slice(0, position)];
      count = Math.min(count, tabs.length);
      for (let tab of tabs.slice(0, count)) {
        chrome.tabs.reload(tab.id, {bypassCache});
      }
    });
  }
};

var forCountTabs = (count, currentTab, callback) => chrome.tabs.query({currentWindow: true}, function(tabs) {
  const activeTabIndex = currentTab.index;
  const startTabIndex = Math.max(0, Math.min(activeTabIndex, tabs.length - count));
  for (let tab of tabs.slice(startTabIndex, startTabIndex + count))
    callback(tab);
});

// Remove tabs before, after, or either side of the currently active tab
var removeTabsRelative = (direction, {tab: activeTab}) => chrome.tabs.query({currentWindow: true}, function(tabs) {
  const shouldDelete =
    (() => { switch (direction) {
      case "before":
        return index => index < activeTab.index;
      case "after":
        return index => index > activeTab.index;
      case "both":
        return index => index !== activeTab.index;
    } })();

  chrome.tabs.remove(tabs.filter(t => !t.pinned && shouldDelete(t.index))
                     .map((t) => t.id));
});

// Selects a tab before or after the currently selected tab.
// - direction: "next", "previous", "first" or "last".
var selectTab = (direction, {count, tab}) => chrome.tabs.query({ currentWindow: true }, function(tabs) {
  if (tabs.length > 1) {
    const toSelect =
      (() => { switch (direction) {
        case "next":
          return (tab.index + count) % tabs.length;
        case "previous":
          return ((tab.index - count) + (count * tabs.length)) % tabs.length;
        case "first":
          return Math.min(tabs.length - 1, count - 1);
        case "last":
          return Math.max(0, tabs.length - count);
      } })();
    chrome.tabs.update(tabs[toSelect].id, {active: true});
  }
});

chrome.webNavigation.onCommitted.addListener(function({tabId, frameId}) {
  const cssConf = {
    frameId,
    code: Settings.get("userDefinedLinkHintCss"),
    runAt: "document_start"
  };
  return chrome.tabs.insertCSS(tabId, cssConf, () => chrome.runtime.lastError);
});

// Symbolic names for the three browser-action icons.
const ENABLED_ICON = "icons/browser_action_enabled.png";
const DISABLED_ICON = "icons/browser_action_disabled.png";
const PARTIAL_ICON = "icons/browser_action_partial.png";

// Convert the three icon PNGs to image data.
const iconImageData = {};
for (let icon of [ENABLED_ICON, DISABLED_ICON, PARTIAL_ICON]) {
  iconImageData[icon] = {};
  for (let scale of [19, 38]) {
    (function(icon, scale) {
      const canvas = document.createElement("canvas");
      canvas.width = (canvas.height = scale);
      // We cannot do the rest of this in the tests.
      if ((chrome.areRunningVimiumTests == null) || !chrome.areRunningVimiumTests) {
        const context = canvas.getContext("2d");
        const image = new Image;
        image.src = icon;
        image.onload = function() {
          context.drawImage(image, 0, 0, scale, scale);
          iconImageData[icon][scale] = context.getImageData(0, 0, scale, scale);
          return document.body.removeChild(canvas);
        };
        return document.body.appendChild(canvas);
      }
    })(icon, scale);
  }
}

var Frames = {
  onConnect(sender, port) {
    const [tabId, frameId] = [sender.tab.id, sender.frameId];
    port.onDisconnect.addListener(() => Frames.unregisterFrame({tabId, frameId, port}));
    port.postMessage({handler: "registerFrameId", chromeFrameId: frameId});
    (portsForTab[tabId] != null ? portsForTab[tabId] : (portsForTab[tabId] = {}))[frameId] = port;

    // Return our onMessage handler for this port.
    return (request, port) => {
      return this[request.handler]({request, tabId, frameId, port, sender});
    };
  },

  registerFrame({tabId, frameId, port}) {
    frameIdsForTab[tabId] = frameIdsForTab[tabId] || [];
    if (!frameIdsForTab[tabId].includes(frameId)) {
      frameIdsForTab[tabId].push(frameId);
    }
    portsForTab[tabId] = portsForTab[tabId] || {};
    return portsForTab[tabId][frameId] = port;
  },

  unregisterFrame({tabId, frameId, port}) {
    // Check that the port trying to unregister the frame hasn't already been replaced by a new frame
    // registering. See #2125.
    const registeredPort = portsForTab[tabId] != null ? portsForTab[tabId][frameId] : undefined;
    if ((registeredPort === port) || !registeredPort) {
      if (tabId in frameIdsForTab)
        frameIdsForTab[tabId] = frameIdsForTab[tabId].filter((fId) => fId !== frameId);
      if (tabId in portsForTab)
        delete portsForTab[tabId][frameId];
    }
    HintCoordinator.unregisterFrame(tabId, frameId);
  },

  isEnabledForUrl({request, tabId, port}) {
    if (request.frameIsFocused)
      urlForTab[tabId] = request.url;
    request.isFirefox = Utils.isFirefox(); // Update the value for Utils.isFirefox in the frontend.
    const enabledState = Exclusions.isEnabledForUrl(request.url);

    if (request.frameIsFocused) {
      if (chrome.browserAction.setIcon) {
        chrome.browserAction.setIcon({tabId, imageData: (function() {
        const enabledStateIcon =
          !enabledState.isEnabledForUrl ?
            DISABLED_ICON
          : enabledState.passKeys.length >= 0 ?
            PARTIAL_ICON
          :
            ENABLED_ICON;
        return iconImageData[enabledStateIcon];
      })()});
      }
    }

    return port.postMessage(Object.assign(request, enabledState));
  },

  domReady({tabId, frameId}) {
    if (frameId == 0) {
      if (tabLoadedHandlers[tabId])
        tabLoadedHandlers[tabId]();
      delete tabLoadedHandlers[tabId];
    }
  },

  linkHintsMessage({request, tabId, frameId}) {
    HintCoordinator.onMessage(tabId, frameId, request);
  },

  // For debugging only. This allows content scripts to log messages to the extension's logging page.
  log({frameId, sender, request: {message}}) {
    BgUtils.log(`${frameId} ${message}`, sender);
  }
};

const handleFrameFocused = function({tabId, frameId}) {
  if (frameIdsForTab[tabId] == null)
    frameIdsForTab[tabId] = [];
  frameIdsForTab[tabId] = cycleToFrame(frameIdsForTab[tabId], frameId);
  // Inform all frames that a frame has received the focus.
  return chrome.tabs.sendMessage(tabId, {name: "frameFocused", focusFrameId: frameId});
};

// Rotate through frames to the frame count places after frameId.
var cycleToFrame = function(frames, frameId, count) {
  // We can't always track which frame chrome has focused, but here we learn that it's frameId; so add an
  // additional offset such that we do indeed start from frameId.
  if (count == null)
    count = 0;
  count = (count + Math.max(0, frames.indexOf(frameId))) % frames.length;
  return [...frames.slice(count), ...frames.slice(0, count)];
};

var HintCoordinator = {
  tabState: {},

  onMessage(tabId, frameId, request) {
    if (request.messageType in this) {
      return this[request.messageType](tabId, frameId, request);
    } else {
      // If there's no handler here, then the message is forwarded to all frames in the sender's tab.
      return this.sendMessage(request.messageType, tabId, request);
    }
  },

  // Post a link-hints message to a particular frame's port. We catch errors in case the frame has gone away.
  postMessage(tabId, frameId, messageType, port, request) {
    if (request == null)
      request = {};
    try {
      return port.postMessage(Object.assign(request, {handler: "linkHintsMessage", messageType}));
    } catch (error) {
      return this.unregisterFrame(tabId, frameId);
    }
  },

  // Post a link-hints message to all participating frames.
  sendMessage(messageType, tabId, request) {
    if (request == null)
      request = {};

    for (let frameId of Object.keys(this.tabState[tabId].ports || {})) {
      const port = this.tabState[tabId].ports[frameId];
      this.postMessage(tabId, parseInt(frameId), messageType, port, request)
    }
  },

  prepareToActivateMode(tabId, originatingFrameId, {modeIndex, isVimiumHelpDialog}) {
    this.tabState[tabId] = {frameIds: frameIdsForTab[tabId].slice(), hintDescriptors: {}, originatingFrameId, modeIndex};
    this.tabState[tabId].ports = {};
    frameIdsForTab[tabId].map(frameId => {
      return this.tabState[tabId].ports[frameId] = portsForTab[tabId][frameId];
    });
    this.sendMessage("getHintDescriptors", tabId, {modeIndex, isVimiumHelpDialog});
  },

  // Receive hint descriptors from all frames and activate link-hints mode when we have them all.
  postHintDescriptors(tabId, frameId, {hintDescriptors}) {
    if (!this.tabState[tabId].frameIds.includes(frameId)) {
      return;
    }
    this.tabState[tabId].hintDescriptors[frameId] = hintDescriptors;
    this.tabState[tabId].frameIds = this.tabState[tabId].frameIds.filter(fId => fId !== frameId);
    if (this.tabState[tabId].frameIds.length === 0) {
      for (frameId of Object.keys(this.tabState[tabId].ports || {})) {
        const port = this.tabState[tabId].ports[frameId];
        if (frameId in this.tabState[tabId].hintDescriptors) {
          hintDescriptors = Object.assign({}, this.tabState[tabId].hintDescriptors);
          // We do not send back the frame's own hint descriptors.  This is faster (approx. speedup 3/2) for
          // link-busy sites like reddit.
          delete hintDescriptors[frameId];
          this.postMessage(tabId, parseInt(frameId), "activateMode", port, {
            originatingFrameId: this.tabState[tabId].originatingFrameId,
            hintDescriptors,
            modeIndex: this.tabState[tabId].modeIndex
          });
        }
      }
    }
  },

  // If an unregistering frame is participating in link-hints mode, then we need to tidy up after it.
  unregisterFrame(tabId, frameId) {
    if (!this.tabState[tabId])
      return;
    if ((this.tabState[tabId].ports != null ? this.tabState[tabId].ports[frameId] : undefined) != null)
      delete this.tabState[tabId].ports[frameId];
    if ((this.tabState[tabId].frameIds != null) && this.tabState[tabId].frameIds.includes(frameId)) {
      // We fake an empty "postHintDescriptors" because the frame has gone away.
      return this.postHintDescriptors(tabId, frameId, {hintDescriptors: []});
    }
  }
};

// Port handler mapping
var portHandlers = {
  completions: handleCompletions,
  frames: Frames.onConnect.bind(Frames)
};

var sendRequestHandlers = {
  runBackgroundCommand(request) { return BackgroundCommands[request.registryEntry.command](request); },
  // getCurrentTabUrl is used by the content scripts to get their full URL, because window.location cannot help
  // with Chrome-specific URLs like "view-source:http:..".
  getCurrentTabUrl({tab}) { return tab.url; },
  openUrlInNewTab: mkRepeatCommand((request, callback) => TabOperations.openUrlInNewTab(request, callback)),
  openUrlInNewWindow(request) { return TabOperations.openUrlInNewWindow(request); },
  openUrlInIncognito(request) { return chrome.windows.create({incognito: true, url: Utils.convertToUrl(request.url)}); },
  openUrlInCurrentTab: TabOperations.openUrlInCurrentTab,
  openOptionsPageInNewTab(request) {
    return chrome.tabs.create({url: chrome.runtime.getURL("pages/options.html"), index: request.tab.index + 1});
  },
  frameFocused: handleFrameFocused,
  nextFrame: BackgroundCommands.nextFrame,
  selectSpecificTab,
  createMark: Marks.create.bind(Marks),
  gotoMark: Marks.goto.bind(Marks),
  // Send a message to all frames in the current tab.
  sendMessageToFrames(request, sender) { return chrome.tabs.sendMessage(sender.tab.id, request.message); }
};

// We always remove chrome.storage.local/findModeRawQueryListIncognito on startup.
chrome.storage.local.remove("findModeRawQueryListIncognito");

// Tidy up tab caches when tabs are removed.  Also remove chrome.storage.local/findModeRawQueryListIncognito if
// there are no remaining incognito-mode windows.  Since the common case is that there are none to begin with,
// we first check whether the key is set at all.
chrome.tabs.onRemoved.addListener(function(tabId) {
  for (let cache of [frameIdsForTab, urlForTab, portsForTab, HintCoordinator.tabState]) { delete cache[tabId]; }
  return chrome.storage.local.get("findModeRawQueryListIncognito", function(items) {
    if (items.findModeRawQueryListIncognito) {
      return chrome.windows != null ? chrome.windows.getAll(null, function(windows) {
        for (let window of windows) {
          if (window.incognito)
            return;
        }
        // There are no remaining incognito-mode tabs, and findModeRawQueryListIncognito is set.
        return chrome.storage.local.remove("findModeRawQueryListIncognito");
      }) : undefined;
    }
  });
});

// Convenience function for development use.
window.runTests = () => open(chrome.runtime.getURL('tests/dom_tests/dom_tests.html'));

//
// Begin initialization.
//

// Show notification on upgrade.
(showUpgradeMessage = function() {
  const currentVersion = Utils.getCurrentVersion();
  // Avoid showing the upgrade notification when previousVersion is undefined, which is the case for new
  // installs.
  if (!Settings.has("previousVersion"))
    Settings.set("previousVersion", currentVersion);
  const previousVersion = Settings.get("previousVersion");
  if (Utils.compareVersions(currentVersion, previousVersion ) === 1) {
    const currentVersionNumbers = currentVersion.split(".");
    const previousVersionNumbers = previousVersion.split(".");
    if (currentVersionNumbers.slice(0, 2).join(".") === previousVersionNumbers.slice(0, 2).join(".")) {
      // We do not show an upgrade message for patch/silent releases.  Such releases have the same major and
      // minor version numbers.  We do, however, update the recorded previous version.
      Settings.set("previousVersion", currentVersion);
    } else {
      const notificationId = "VimiumUpgradeNotification";
      const notification = {
        type: "basic",
        iconUrl: chrome.runtime.getURL("icons/vimium.png"),
        title: "Vimium Upgrade",
        message: `Vimium has been upgraded to version ${currentVersion}. Click here for more information.`,
        isClickable: true
      };
      if (chrome.notifications && chrome.notifications.create) {
        chrome.notifications.create(notificationId, notification, function() {
          if (!chrome.runtime.lastError) {
            Settings.set("previousVersion", currentVersion);
            chrome.notifications.onClicked.addListener(function(id) {
              if (id === notificationId) {
                chrome.tabs.query({ active: true, currentWindow: true }, function(...args) {
                  const [tab] = args[0];
                  return TabOperations.openUrlInNewTab({tab, tabId: tab.id, url: "https://github.com/philc/vimium/blob/master/CHANGELOG.md"});
                });
              }
            });
          }
        });
      } else {
        // We need to wait for the user to accept the "notifications" permission.
        chrome.permissions.onAdded.addListener(showUpgradeMessage);
      }
    }
  }
})();

// The install date is shown on the logging page.
chrome.runtime.onInstalled.addListener(function({reason}) {
  if (!["chrome_update", "shared_module_update"].includes(reason))
    chrome.storage.local.set({installDate: new Date().toString()});
});

Object.assign(global, {TabOperations, Frames});

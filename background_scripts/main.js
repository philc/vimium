// NOTE(philc): This file has many superfluous return statements in its functions, as a result of
// converting from coffeescript to es6. Many can be removed, but I didn't take the time to
// diligently track down precisely which return statements could be removed when I was doing the
// conversion.

import * as TabOperations from "./tab_operations.js";

// Allow Vimium's content scripts to access chrome.storage.session. Otherwise,
// chrome.storage.session will be null in content scripts.
chrome.storage.session.setAccessLevel({ accessLevel: "TRUSTED_AND_UNTRUSTED_CONTEXTS" });

// The browser may have tabs already open. We inject the content scripts and Vimium's CSS
// immediately so that the extension is running on the pages immediately after install, rather than
// having to reload those pages.
chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  console.log("On installed");
  // See https://developer.chrome.com/extensions/runtime#event-onInstalled
  if (["chrome_update", "shared_module_update"].includes(reason)) return;
  // TODO(philc): Why do we return here if it's Firefox? I think this should run on Firefox.
  if (Utils.isFirefox()) return;
  const manifest = chrome.runtime.getManifest();
  const contentScriptConfig = manifest.content_scripts[0];
  const contentScripts = contentScriptConfig.js;
  const cssFiles = contentScriptConfig.css;
  await Settings.onLoaded();

  // The scripting.executeScript and scripting.insertCSS APIs can fail if we don't have permissions
  // to run scripts in a given tab. Examples are: chrome:// URLs, file:// pages (if the user hasn't
  // granted Vimium access to file URLs), and probably incognito tabs (unconfirmed). Calling these
  // APIs on such tabs results in an error getting logged on the background page. To avoid this
  // noise, we swallow the failures. We could instead try to determine if the tab is scriptable by
  // checking its URL scheme before calling these APIs, but that approach has some nuance to it.
  // This is simpler.
  const swallowError = (error) => {};

  const tabs = await chrome.tabs.query({ status: "complete" });
  for (const tab of tabs) {
    const target = { tabId: tab.id, allFrames: true };

    // Inject all of our content javascripts.
    chrome.scripting.executeScript({
      files: contentScripts,
      target: target,
    }).catch(swallowError);

    // Inject our extension's CSS.
    chrome.scripting.insertCSS({
      files: cssFiles,
      target: target,
    }).catch(swallowError);

    // Inject the user's link hint CSS.
    chrome.scripting.insertCSS({
      css: Settings.get("userDefinedLinkHintCss"),
      target: target,
    }).catch(swallowError);
  }
});

const frameIdsForTab = {};
globalThis.portsForTab = {};
globalThis.urlForTab = {};

// This is exported for use by "marks.js".
globalThis.tabLoadedHandlers = {}; // tabId -> function()

// A Vimium secret, available only within the current browser session. The secret is a generated
// strong random string.
const randomArray = globalThis.crypto.getRandomValues(new Uint8Array(32)); // 32-byte random token.
const secretToken = randomArray.reduce((a, b) => a.toString(16) + b.toString(16));
chrome.storage.session.set({ vimiumSecret: secretToken });

const completionSources = {
  bookmarks: new BookmarkCompleter(),
  history: new HistoryCompleter(),
  domains: new DomainCompleter(),
  tabs: new TabCompleter(),
  searchEngines: new SearchEngineCompleter(),
};

const completers = {
  omni: new MultiCompleter([
    completionSources.bookmarks,
    completionSources.history,
    completionSources.domains,
    completionSources.tabs,
    completionSources.searchEngines,
  ]),
  bookmarks: new MultiCompleter([completionSources.bookmarks]),
  tabs: new MultiCompleter([completionSources.tabs]),
};

const completionHandlers = {
  filter(completer, request, port) {
    // TODO(philc): Do we need any of these return statements?
    return completer.filter(request, function (response) {
      // NOTE(smblott): response contains `relevancyFunction` (function) properties which cause postMessage,
      // below, to fail in Firefox. See #2576.  We cannot simply delete these methods, as they're needed
      // elsewhere.  Converting the response to JSON and back is a quick and easy way to sanitize the object.
      response = JSON.parse(JSON.stringify(response));
      // We use try here because this may fail if the sender has already navigated away from the original page.
      // This can happen, for example, when posting completion suggestions from the SearchEngineCompleter
      // (which is done asynchronously).
      try {
        return port.postMessage(Object.assign(request, response, { handler: "completions" }));
      } catch (error) {}
    });
  },

  refresh(completer, _, port) {
    completer.refresh(port);
  },
  cancel(completer, _, port) {
    completer.cancel(port);
  },
};

const handleCompletions = (sender) => (request, port) =>
  completionHandlers[request.handler](completers[request.name], request, port);

chrome.runtime.onConnect.addListener(async function (port) {
  await Settings.onLoaded();
  if (portHandlers[port.name]) {
    return port.onMessage.addListener(portHandlers[port.name](port.sender, port));
  }
});

chrome.runtime.onMessage.addListener(function (request, sender, sendResponse) {
  request = Object.assign({ count: 1, frameId: sender.frameId }, request, {
    tab: sender.tab,
    tabId: sender.tab.id,
  });
  if (sendRequestHandlers[request.handler]) {
    sendResponse(sendRequestHandlers[request.handler](request, sender));
  }
  // Ensure that the sendResponse callback is freed.
  return false;
});

const onURLChange = (details) => {
  // sendMessage will throw "Error: Could not establish connection. Receiving end does not exist."
  // if there is no Vimium content script loaded in the given tab. This can occur if the user
  // navigated to a page where Vimium doesn't have permissions, like chrome:// URLs. This error is
  // noisy and mysterious (it usually doesn't have a valid line number), so we silence it.
  chrome.tabs.sendMessage(details.tabId, { name: "checkEnabledAfterURLChange" })
    .catch(() => {});
};

// Re-check whether Vimium is enabled for a frame when the URL changes without a reload.
chrome.webNavigation.onHistoryStateUpdated.addListener(onURLChange); // history.pushState.
chrome.webNavigation.onReferenceFragmentUpdated.addListener(onURLChange); // Hash changed.

// Cache "content_scripts/vimium.css" in chrome.storage.session for UI components.
(function () {
  const url = chrome.runtime.getURL("content_scripts/vimium.css");
  fetch(url).then(async (response) => {
    if (response.ok) {
      chrome.storage.session.set({ vimiumCSSInChromeStorage: await response.text() });
    }
  });
})();

const muteTab = (tab) => chrome.tabs.update(tab.id, { muted: !tab.mutedInfo.muted });
const toggleMuteTab = function ({ tab: currentTab, registryEntry, tabId, frameId }) {
  if ((registryEntry.options.all != null) || (registryEntry.options.other != null)) {
    // If there are any audible, unmuted tabs, then we mute them; otherwise we unmute any muted tabs.
    chrome.tabs.query({ audible: true }, function (tabs) {
      let tab;
      if (registryEntry.options.other != null) {
        tabs = tabs.filter((t) => t.id !== currentTab.id);
      }
      const audibleUnmutedTabs = tabs.filter((t) => t.audible && !t.mutedInfo.muted);
      if (audibleUnmutedTabs.length >= 0) {
        chrome.tabs.sendMessage(tabId, {
          frameId,
          name: "showMessage",
          message: `Muting ${audibleUnmutedTabs.length} tab(s).`,
        });
        for (tab of audibleUnmutedTabs) {
          muteTab(tab);
        }
      } else {
        chrome.tabs.sendMessage(tabId, {
          frameId,
          name: "showMessage",
          message: "Unmuting all muted tabs.",
        });
        for (tab of tabs) {
          if (tab.mutedInfo.muted) {
            muteTab(tab);
          }
        }
      }
    });
  } else {
    if (currentTab.mutedInfo.muted) {
      chrome.tabs.sendMessage(tabId, { frameId, name: "showMessage", message: "Unmuted tab." });
    } else {
      chrome.tabs.sendMessage(tabId, { frameId, name: "showMessage", message: "Muted tab." });
    }
    muteTab(currentTab);
  }
};

//
// Selects the tab with the ID specified in request.id
//
const selectSpecificTab = (request) =>
  chrome.tabs.get(request.id, function (tab) {
    if (chrome.windows != null) {
      chrome.windows.update(tab.windowId, { focused: true });
    }
    return chrome.tabs.update(request.id, { active: true });
  });

const moveTab = function ({ count, tab, registryEntry }) {
  if (registryEntry.command === "moveTabLeft") {
    count = -count;
  }
  return chrome.tabs.query({ currentWindow: true }, function (tabs) {
    const pinnedCount = (tabs.filter((tab) => tab.pinned)).length;
    const minIndex = tab.pinned ? 0 : pinnedCount;
    const maxIndex = (tab.pinned ? pinnedCount : tabs.length) - 1;
    return chrome.tabs.move(tab.id, {
      index: Math.max(minIndex, Math.min(maxIndex, tab.index + count)),
    });
  });
};

var mkRepeatCommand = (command) => (function (request) {
  request.count--;
  if (request.count >= 0) {
    return command(request, (request) => (mkRepeatCommand(command))(request));
  }
});

// These are commands which are bound to keystrokes which must be handled by the background page.
// They are mapped in commands.coffee.
const BackgroundCommands = {
  // Create a new tab.  Also, with:
  //     map X createTab http://www.bbc.com/news
  // create a new tab with the given URL.
  createTab: mkRepeatCommand(function (request, callback) {
    if (request.urls == null) {
      if (request.url) {
        // If the request contains a URL, then use it.
        request.urls = [request.url];
      } else {
        // Otherwise, if we have a registryEntry containing URLs, then use them.
        const urlList = request.registryEntry.optionList.filter((opt) => Utils.isUrl(opt));
        if (urlList.length > 0) {
          request.urls = urlList;
        } else {
          // Otherwise, just create a new tab.
          const newTabUrl = Settings.get("newTabUrl");
          if (newTabUrl === "pages/blank.html") {
            // "pages/blank.html" does not work in incognito mode, so fall back to "chrome://newtab" instead.
            request.urls = [
              request.tab.incognito ? "chrome://newtab" : chrome.runtime.getURL(newTabUrl),
            ];
          } else {
            request.urls = [newTabUrl];
          }
        }
      }
    }

    if (request.registryEntry.options.incognito || request.registryEntry.options.window) {
      const windowConfig = {
        url: request.urls,
        incognito: request.registryEntry.options.incognito || false,
      };
      return chrome.windows.create(windowConfig, () => callback(request));
    } else {
      let openNextUrl;
      const urls = request.urls.slice().reverse();
      if (request.position == null) {
        request.position = request.registryEntry.options.position;
      }
      return (openNextUrl = function (request) {
        if (urls.length > 0) {
          return TabOperations.openUrlInNewTab(
            Object.assign(request, { url: urls.pop() }),
            openNextUrl,
          );
        } else {
          return callback(request);
        }
      })(request);
    }
  }),

  duplicateTab: mkRepeatCommand((request, callback) => {
    return chrome.tabs.duplicate(
      request.tabId,
      (tab) => callback(Object.assign(request, { tab, tabId: tab.id })),
    );
  }),

  moveTabToNewWindow({ count, tab }) {
    chrome.tabs.query({ currentWindow: true }, function (tabs) {
      const activeTabIndex = tab.index;
      const startTabIndex = Math.max(0, Math.min(activeTabIndex, tabs.length - count));
      [tab, ...tabs] = tabs.slice(startTabIndex, startTabIndex + count);
      chrome.windows.create({ tabId: tab.id, incognito: tab.incognito }, function (window) {
        chrome.tabs.move(tabs.map((t) => t.id), { windowId: window.id, index: -1 });
      });
    });
  },

  nextTab(request) {
    return selectTab("next", request);
  },
  previousTab(request) {
    return selectTab("previous", request);
  },
  firstTab(request) {
    return selectTab("first", request);
  },
  lastTab(request) {
    return selectTab("last", request);
  },
  removeTab({ count, tab }) {
    return forCountTabs(count, tab, (tab) => chrome.tabs.remove(tab.id));
  },
  restoreTab: mkRepeatCommand((request, callback) =>
    chrome.sessions.restore(null, callback(request))
  ),
  togglePinTab({ count, tab }) {
    return forCountTabs(count, tab, (tab) => chrome.tabs.update(tab.id, { pinned: !tab.pinned }));
  },
  toggleMuteTab,
  moveTabLeft: moveTab,
  moveTabRight: moveTab,

  nextFrame({ count, frameId, tabId }) {
    frameIdsForTab[tabId] = cycleToFrame(frameIdsForTab[tabId], frameId, count);
    return chrome.tabs.sendMessage(tabId, {
      name: "focusFrame",
      frameId: frameIdsForTab[tabId][0],
      highlight: true,
    });
  },

  closeTabsOnLeft(request) {
    return removeTabsRelative("before", request);
  },
  closeTabsOnRight(request) {
    return removeTabsRelative("after", request);
  },
  closeOtherTabs(request) {
    return removeTabsRelative("both", request);
  },

  visitPreviousTab({ count, tab }) {
    const tabIds = BgUtils.tabRecency.getTabsByRecency().filter((tabId) => tabId !== tab.id);
    if (tabIds.length > 0) {
      return selectSpecificTab({ id: tabIds[(count - 1) % tabIds.length] });
    }
  },

  reload({ count, tabId, registryEntry, tab: { windowId } }) {
    const bypassCache = registryEntry.options.hard != null ? registryEntry.options.hard : false;
    return chrome.tabs.query({ windowId }, function (tabs) {
      const position = (function () {
        for (let index = 0; index < tabs.length; index++) {
          const tab = tabs[index];
          if (tab.id === tabId) return index;
        }
      })();
      tabs = [...tabs.slice(position), ...tabs.slice(0, position)];
      count = Math.min(count, tabs.length);
      for (let tab of tabs.slice(0, count)) {
        chrome.tabs.reload(tab.id, { bypassCache });
      }
    });
  },
};

var forCountTabs = (count, currentTab, callback) =>
  chrome.tabs.query({ currentWindow: true }, function (tabs) {
    const activeTabIndex = currentTab.index;
    const startTabIndex = Math.max(0, Math.min(activeTabIndex, tabs.length - count));
    for (let tab of tabs.slice(startTabIndex, startTabIndex + count)) {
      callback(tab);
    }
  });

// Remove tabs before, after, or either side of the currently active tab
var removeTabsRelative = (direction, { tab: activeTab }) =>
  chrome.tabs.query({ currentWindow: true }, function (tabs) {
    const shouldDelete = (() => {
      switch (direction) {
        case "before":
          return (index) => index < activeTab.index;
        case "after":
          return (index) => index > activeTab.index;
        case "both":
          return (index) => index !== activeTab.index;
      }
    })();

    chrome.tabs.remove(
      tabs.filter((t) => !t.pinned && shouldDelete(t.index))
        .map((t) => t.id),
    );
  });

// Selects a tab before or after the currently selected tab.
// - direction: "next", "previous", "first" or "last".
var selectTab = (direction, { count, tab }) =>
  chrome.tabs.query({ currentWindow: true }, function (tabs) {
    if (tabs.length > 1) {
      const toSelect = (() => {
        switch (direction) {
          case "next":
            return (tab.index + count) % tabs.length;
          case "previous":
            return ((tab.index - count) + (count * tabs.length)) % tabs.length;
          case "first":
            return Math.min(tabs.length - 1, count - 1);
          case "last":
            return Math.max(0, tabs.length - count);
        }
      })();
      chrome.tabs.update(tabs[toSelect].id, { active: true });
    }
  });

chrome.webNavigation.onCommitted.addListener(async ({ tabId, frameId }) => {
  // Vimium can't run on all tabs (e.g. chrome:// URLs). insertCSS will throw an error on such tabs,
  // which is expected, and noise. Swallow that error.
  const swallowError = () => {};
  await Settings.onLoaded();
  await chrome.scripting.insertCSS({
    css: Settings.get("userDefinedLinkHintCss"),
    target: {
      tabId: tabId,
      frameIds: [frameId],
    },
  }).catch(swallowError);
});

const Frames = {
  onConnect(sender, port) {
    const [tabId, frameId] = [sender.tab.id, sender.frameId];
    port.onDisconnect.addListener(() => Frames.unregisterFrame({ tabId, frameId, port }));
    const message = { handler: "registerFrameId", chromeFrameId: frameId };
    let firefoxVersion;
    if (Utils.isFirefox()) {
      firefoxVersion = Utils.firefoxVersion();
      message.firefoxVersion = firefoxVersion;
    }
    if (typeof firefoxVersion === "object") {
      firefoxVersion.then(() => {
        message.firefoxVersion = Utils.firefoxVersion();
        port.postMessage(message);
      });
    } else {
      port.postMessage(message);
    }
    (portsForTab[tabId] != null ? portsForTab[tabId] : (portsForTab[tabId] = {}))[frameId] = port;

    // Return our onMessage handler for this port.
    return (request, port) => {
      return this[request.handler]({ request, tabId, frameId, port, sender });
    };
  },

  registerFrame({ tabId, frameId, port }) {
    frameIdsForTab[tabId] = frameIdsForTab[tabId] || [];
    if (!frameIdsForTab[tabId].includes(frameId)) {
      frameIdsForTab[tabId].push(frameId);
    }
    portsForTab[tabId] = portsForTab[tabId] || {};
    return portsForTab[tabId][frameId] = port;
  },

  unregisterFrame({ tabId, frameId, port }) {
    // Check that the port trying to unregister the frame hasn't already been replaced by a new
    // frame registering. See #2125.
    const registeredPort = portsForTab[tabId] != null ? portsForTab[tabId][frameId] : undefined;
    if ((registeredPort === port) || !registeredPort) {
      if (tabId in frameIdsForTab) {
        frameIdsForTab[tabId] = frameIdsForTab[tabId].filter((fId) => fId !== frameId);
      }
      if (tabId in portsForTab) {
        delete portsForTab[tabId][frameId];
      }
    }
    HintCoordinator.unregisterFrame(tabId, frameId);
  },

  isEnabledForUrl({ request, tabId, port }) {
    if (request.frameIsFocused) {
      urlForTab[tabId] = request.url;
    }
    request.isFirefox = Utils.isFirefox(); // Update the value for Utils.isFirefox in the frontend.
    const enabledState = Exclusions.isEnabledForUrl(request.url);

    if (request.frameIsFocused) {
      let whichIcon;
      if (!enabledState.isEnabledForUrl) {
        whichIcon = "disabled";
      } else if (enabledState.passKeys.length > 0) {
        whichIcon = "partial";
      } else {
        whichIcon = "enabled";
      }

      const iconSet = {
        "enabled": {
          "16": "../icons/action_enabled_16.png",
          "32": "../icons/action_enabled_32.png",
        },
        "partial": {
          "16": "../icons/action_partial_16.png",
          "32": "../icons/action_partial_32.png",
        },
        "disabled": {
          "16": "../icons/action_disabled_16.png",
          "32": "../icons/action_disabled_32.png",
        },
      };
      chrome.action.setIcon({ path: iconSet[whichIcon], tabId: tabId });
    }

    return port.postMessage(Object.assign(request, enabledState));
  },

  domReady({ tabId, frameId }) {
    if (frameId == 0) {
      if (tabLoadedHandlers[tabId]) {
        tabLoadedHandlers[tabId]();
      }
      delete tabLoadedHandlers[tabId];
    }
  },

  linkHintsMessage({ request, tabId, frameId }) {
    HintCoordinator.onMessage(tabId, frameId, request);
  },

  // For debugging only. This allows content scripts to log messages to the extension's logging
  // page.
  log({ frameId, sender, request: { message } }) {
    BgUtils.log(`${frameId} ${message}`, sender);
  },
};

const handleFrameFocused = function ({ tabId, frameId }) {
  if (frameIdsForTab[tabId] == null) {
    frameIdsForTab[tabId] = [];
  }
  frameIdsForTab[tabId] = cycleToFrame(frameIdsForTab[tabId], frameId);
  // Inform all frames that a frame has received the focus.
  return chrome.tabs.sendMessage(tabId, { name: "frameFocused", focusFrameId: frameId });
};

// Rotate through frames to the frame count places after frameId.
var cycleToFrame = function (frames, frameId, count) {
  // We can't always track which frame chrome has focused, but here we learn that it's frameId; so
  // add an additional offset such that we do indeed start from frameId.
  if (count == null) {
    count = 0;
  }
  count = (count + Math.max(0, frames.indexOf(frameId))) % frames.length;
  return [...frames.slice(count), ...frames.slice(0, count)];
};

var HintCoordinator = {
  tabState: {},

  onMessage(tabId, frameId, request) {
    if (request.messageType in this) {
      return this[request.messageType](tabId, frameId, request);
    } else {
      // If there's no handler here, then the message is forwarded to all frames in the sender's
      // tab.
      return this.sendMessage(request.messageType, tabId, request);
    }
  },

  // Post a link-hints message to a particular frame's port. We catch errors in case the frame has
  // gone away.
  postMessage(tabId, frameId, messageType, port, request) {
    if (request == null) {
      request = {};
    }
    try {
      return port.postMessage(Object.assign(request, { handler: "linkHintsMessage", messageType }));
    } catch (error) {
      return this.unregisterFrame(tabId, frameId);
    }
  },

  // Post a link-hints message to all participating frames.
  sendMessage(messageType, tabId, request) {
    if (request == null) {
      request = {};
    }

    for (let frameId of Object.keys(this.tabState[tabId].ports || {})) {
      const port = this.tabState[tabId].ports[frameId];
      this.postMessage(tabId, parseInt(frameId), messageType, port, request);
    }
  },

  prepareToActivateMode(tabId, originatingFrameId, { modeIndex, isVimiumHelpDialog }) {
    this.tabState[tabId] = {
      frameIds: frameIdsForTab[tabId].slice(),
      hintDescriptors: {},
      originatingFrameId,
      modeIndex,
    };
    this.tabState[tabId].ports = {};
    frameIdsForTab[tabId].map((frameId) => {
      return this.tabState[tabId].ports[frameId] = portsForTab[tabId][frameId];
    });
    this.sendMessage("getHintDescriptors", tabId, { modeIndex, isVimiumHelpDialog });
  },

  // Receive hint descriptors from all frames and activate link-hints mode when we have them all.
  postHintDescriptors(tabId, frameId, { hintDescriptors }) {
    if (!this.tabState[tabId].frameIds.includes(frameId)) {
      return;
    }
    this.tabState[tabId].hintDescriptors[frameId] = hintDescriptors;
    this.tabState[tabId].frameIds = this.tabState[tabId].frameIds.filter((fId) => fId !== frameId);
    if (this.tabState[tabId].frameIds.length === 0) {
      for (frameId of Object.keys(this.tabState[tabId].ports || {})) {
        const port = this.tabState[tabId].ports[frameId];
        if (frameId in this.tabState[tabId].hintDescriptors) {
          hintDescriptors = Object.assign({}, this.tabState[tabId].hintDescriptors);
          // We do not send back the frame's own hint descriptors. This is faster (approx. speedup
          // 3/2) for link-busy sites like reddit.
          delete hintDescriptors[frameId];
          this.postMessage(tabId, parseInt(frameId), "activateMode", port, {
            originatingFrameId: this.tabState[tabId].originatingFrameId,
            hintDescriptors,
            modeIndex: this.tabState[tabId].modeIndex,
          });
        }
      }
    }
  },

  // If an unregistering frame is participating in link-hints mode, then we need to tidy up after
  // it.
  unregisterFrame(tabId, frameId) {
    if (!this.tabState[tabId]) {
      return;
    }
    if (
      (this.tabState[tabId].ports != null ? this.tabState[tabId].ports[frameId] : undefined) != null
    ) {
      delete this.tabState[tabId].ports[frameId];
    }
    if (
      (this.tabState[tabId].frameIds != null) && this.tabState[tabId].frameIds.includes(frameId)
    ) {
      // We fake an empty "postHintDescriptors" because the frame has gone away.
      return this.postHintDescriptors(tabId, frameId, { hintDescriptors: [] });
    }
  },
};

// Port handler mapping
var portHandlers = {
  completions: handleCompletions,
  frames: Frames.onConnect.bind(Frames),
};

var sendRequestHandlers = {
  runBackgroundCommand(request) {
    return BackgroundCommands[request.registryEntry.command](request);
  },
  // getCurrentTabUrl is used by the content scripts to get their full URL, because window.location
  // cannot help with Chrome-specific URLs like "view-source:http:..".
  getCurrentTabUrl({ tab }) {
    return tab.url;
  },
  openUrlInNewTab: mkRepeatCommand((request, callback) =>
    TabOperations.openUrlInNewTab(request, callback)
  ),
  openUrlInNewWindow(request) {
    return TabOperations.openUrlInNewWindow(request);
  },
  openUrlInIncognito(request) {
    return chrome.windows.create({ incognito: true, url: Utils.convertToUrl(request.url) });
  },
  openUrlInCurrentTab: TabOperations.openUrlInCurrentTab,
  openOptionsPageInNewTab(request) {
    return chrome.tabs.create({
      url: chrome.runtime.getURL("pages/options.html"),
      index: request.tab.index + 1,
    });
  },
  frameFocused: handleFrameFocused,
  nextFrame: BackgroundCommands.nextFrame,
  selectSpecificTab,
  createMark: Marks.create.bind(Marks),
  gotoMark: Marks.goto.bind(Marks),
  // Send a message to all frames in the current tab.
  sendMessageToFrames(request, sender) {
    return chrome.tabs.sendMessage(sender.tab.id, request.message);
  },
};

// Tidy up tab caches when tabs are removed. Also remove
// chrome.storage.local/findModeRawQueryListIncognito if there are no remaining incognito-mode
// windows. Since the common case is that there are none to begin with, we first check whether the
// key is set at all.
chrome.tabs.onRemoved.addListener(function (tabId) {
  for (let cache of [frameIdsForTab, urlForTab, portsForTab, HintCoordinator.tabState]) {
    delete cache[tabId];
  }
  return chrome.storage.session.get("findModeRawQueryListIncognito", function (items) {
    if (items.findModeRawQueryListIncognito) {
      return chrome.windows != null
        ? chrome.windows.getAll(null, function (windows) {
          for (let window of windows) {
            if (window.incognito) {
              return;
            }
          }
          // There are no remaining incognito-mode tabs, and findModeRawQueryListIncognito is set.
          return chrome.storage.session.remove("findModeRawQueryListIncognito");
        })
        : undefined;
    }
  });
});

// Convenience function for development use.
globalThis.runTests = () => open(chrome.runtime.getURL("tests/dom_tests/dom_tests.html"));

//
// Begin initialization.
//

// Show notification on upgrade.
let showUpgradeMessageIfNecessary;
showUpgradeMessageIfNecessary = function () {
  const currentVersion = Utils.getCurrentVersion();
  const previousVersion = Settings.get("previousVersion");

  if (Utils.compareVersions(currentVersion, previousVersion) != 1) {
    return;
  }
  const currentVersionNumbers = currentVersion.split(".");
  const previousVersionNumbers = previousVersion.split(".");
  if (
    currentVersionNumbers.slice(0, 2).join(".") === previousVersionNumbers.slice(0, 2).join(".")
  ) {
    // We do not show an upgrade message for patch/silent releases. Such releases have the same
    // major and minor version numbers. We do, however, update the recorded previous version.
    Settings.set("previousVersion", currentVersion);
  } else {
    const notificationId = "VimiumUpgradeNotification";
    const notification = {
      type: "basic",
      iconUrl: chrome.runtime.getURL("icons/vimium.png"),
      title: "Vimium Upgrade",
      message:
        `Vimium has been upgraded to version ${currentVersion}. Click here for more information.`,
      isClickable: true,
    };
    if (chrome.notifications && chrome.notifications.create) {
      chrome.notifications.create(notificationId, notification, function () {
        if (!chrome.runtime.lastError) {
          Settings.set("previousVersion", currentVersion);
          chrome.notifications.onClicked.addListener(function (id) {
            if (id === notificationId) {
              chrome.tabs.query({ active: true, currentWindow: true }, function (...args) {
                const [tab] = args[0];
                return TabOperations.openUrlInNewTab({
                  tab,
                  tabId: tab.id,
                  url: "https://github.com/philc/vimium/blob/master/CHANGELOG.md",
                });
              });
            }
          });
        }
      });
    } else {
      // We need to wait for the user to accept the "notifications" permission.
      chrome.permissions.onAdded.addListener(showUpgradeMessageIfNecessary);
    }
  }
};

// The install date is shown on the logging page.
chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  // Setup code for the background service worker.
  await Settings.onLoaded();
  await Commands.init();

  // Avoid showing the upgrade notification when previousVersion is undefined, which is the case for
  // new installs.
  if (Settings.get("previousVersion") == null) {
    await Settings.set("previousVersion", Utils.getCurrentVersion());
  }
  showUpgradeMessageIfNecessary();
});

Object.assign(globalThis, { TabOperations, Frames });

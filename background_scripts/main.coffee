root = exports ? window

# The browser may have tabs already open. We inject the content scripts immediately so that they work straight
# away.
chrome.runtime.onInstalled.addListener ({ reason }) ->
  # See https://developer.chrome.com/extensions/runtime#event-onInstalled
  return if reason in [ "chrome_update", "shared_module_update" ]
  manifest = chrome.runtime.getManifest()
  # Content scripts loaded on every page should be in the same group. We assume it is the first.
  contentScripts = manifest.content_scripts[0]
  jobs = [ [ chrome.tabs.executeScript, contentScripts.js ], [ chrome.tabs.insertCSS, contentScripts.css ] ]
  # Chrome complains if we don't evaluate chrome.runtime.lastError on errors (and we get errors for tabs on
  # which Vimium cannot run).
  checkLastRuntimeError = -> chrome.runtime.lastError
  chrome.tabs.query { status: "complete" }, (tabs) ->
    for tab in tabs
      for [ func, files ] in jobs
        for file in files
          func tab.id, { file: file, allFrames: contentScripts.all_frames }, checkLastRuntimeError

currentVersion = Utils.getCurrentVersion()
frameIdsForTab = {}
root.urlForTab = {}
topFramePortForTab = {}

# This is exported for use by "marks.coffee".
root.tabLoadedHandlers = {} # tabId -> function()

# A secret, available only within the current instantiation of Vimium.  The secret is big, likely unguessable
# in practice, but less than 2^31.
chrome.storage.local.set
  vimiumSecret: Math.floor Math.random() * 2000000000

completionSources =
  bookmarks: new BookmarkCompleter
  history: new HistoryCompleter
  domains: new DomainCompleter
  tabs: new TabCompleter
  searchEngines: new SearchEngineCompleter

completers =
  omni: new MultiCompleter [
    completionSources.bookmarks
    completionSources.history
    completionSources.domains
    completionSources.searchEngines
    ]
  bookmarks: new MultiCompleter [completionSources.bookmarks]
  tabs: new MultiCompleter [completionSources.tabs]

completionHandlers =
  filter: (completer, request, port) ->
    completer.filter request, (response) ->
      # We use try here because this may fail if the sender has already navigated away from the original page.
      # This can happen, for example, when posting completion suggestions from the SearchEngineCompleter
      # (which is done asynchronously).
      try
        port.postMessage extend request, extend response, handler: "completions"

  refresh: (completer, _, port) -> completer.refresh port
  cancel: (completer, _, port) -> completer.cancel port

handleCompletions = (sender) -> (request, port) ->
  completionHandlers[request.handler] completers[request.name], request, port

chrome.runtime.onConnect.addListener (port, name) ->
  if (portHandlers[port.name])
    port.onMessage.addListener portHandlers[port.name] port.sender, port

chrome.runtime.onMessage.addListener((request, sender, sendResponse) ->
  request = extend {count: 1}, extend request, tab: sender.tab, tabId: sender.tab.id
  if (sendRequestHandlers[request.handler])
    sendResponse(sendRequestHandlers[request.handler](request, sender))
  # Ensure the sendResponse callback is freed.
  return false)

#
# Used by the content scripts to get their full URL. This is needed for URLs like "view-source:http:# .."
# because window.location doesn't know anything about the Chrome-specific "view-source:".
#
getCurrentTabUrl = (request, sender) -> sender.tab.url

onURLChange = (details) ->
  chrome.tabs.sendMessage details.tabId, name: "checkEnabledAfterURLChange"

# Re-check whether Vimium is enabled for a frame when the url changes without a reload.
chrome.webNavigation.onHistoryStateUpdated.addListener onURLChange # history.pushState.
chrome.webNavigation.onReferenceFragmentUpdated.addListener onURLChange # Hash changed.

# Retrieves the help dialog HTML template from a file, and populates it with the latest keybindings.
# This is called by options.coffee.
root.helpDialogHtml = (showUnboundCommands, showCommandNames, customTitle) ->
  commandsToKey = {}
  for own key of Commands.keyToCommandRegistry
    command = Commands.keyToCommandRegistry[key].command
    commandsToKey[command] = (commandsToKey[command] || []).concat(key)

  replacementStrings =
    version: currentVersion
    title: customTitle || "Help"

  for own group of Commands.commandGroups
    replacementStrings[group] =
        helpDialogHtmlForCommandGroup(group, commandsToKey, Commands.availableCommands,
                                      showUnboundCommands, showCommandNames)

  replacementStrings

#
# Generates HTML for a given set of commands. commandGroups are defined in commands.js
#
helpDialogHtmlForCommandGroup = (group, commandsToKey, availableCommands,
    showUnboundCommands, showCommandNames) ->
  html = []
  for command in Commands.commandGroups[group]
    bindings = (commandsToKey[command] || [""]).join(", ")
    if (showUnboundCommands || commandsToKey[command])
      isAdvanced = Commands.advancedCommands.indexOf(command) >= 0
      description = availableCommands[command].description
      if bindings.length < 12
        helpDialogHtmlForCommand html, isAdvanced, bindings, description, showCommandNames, command
      else
        # If the length of the bindings is too long, then we display the bindings on a separate row from the
        # description.  This prevents the column alignment from becoming out of whack.
        helpDialogHtmlForCommand html, isAdvanced, bindings, "", false, ""
        helpDialogHtmlForCommand html, isAdvanced, "", description, showCommandNames, command
  html.join("\n")

helpDialogHtmlForCommand = (html, isAdvanced, bindings, description, showCommandNames, command) ->
  html.push "<tr class='vimiumReset #{"advanced" if isAdvanced}'>"
  if description
    html.push "<td class='vimiumReset'>", Utils.escapeHtml(bindings), "</td>"
    html.push "<td class='vimiumReset'>#{if description and bindings then ':' else ''}</td><td class='vimiumReset'>", description
    html.push("<span class='vimiumReset commandName'>(#{command})</span>") if showCommandNames
  else
    html.push "<td class='vimiumReset' colspan='3' style='text-align: left;'>", Utils.escapeHtml(bindings)
  html.push("</td></tr>")

#
# Fetches the contents of a file bundled with this extension.
#
fetchFileContents = (extensionFileName) ->
  req = new XMLHttpRequest()
  req.open("GET", chrome.runtime.getURL(extensionFileName), false) # false => synchronous
  req.send()
  req.responseText

TabOperations =
  # Opens the url in the current tab.
  openUrlInCurrentTab: (request) ->
    chrome.tabs.update request.tabId, url: Utils.convertToUrl request.url

  # Opens request.url in new tab and switches to it if request.selected is true.
  openUrlInNewTab: (request, callback = (->)) ->
    tabConfig =
      url: Utils.convertToUrl request.url
      index: request.tab.index + 1
      selected: true
      windowId: request.tab.windowId
      openerTabId: request.tab.id
    chrome.tabs.create tabConfig, callback

#
# Copies or pastes some data (request.data) to/from the clipboard.
# We return null to avoid the return value from the copy operations being passed to sendResponse.
#
copyToClipboard = (request) -> Clipboard.copy(request.data); null
pasteFromClipboard = (request) -> Clipboard.paste()

#
# Selects the tab with the ID specified in request.id
#
selectSpecificTab = (request) ->
  chrome.tabs.get(request.id, (tab) ->
    chrome.windows.update(tab.windowId, { focused: true })
    chrome.tabs.update(request.id, { selected: true }))

repeatCommand = (command) -> (request) ->
  if 0 < request.count--
    command request, (request) -> (repeatCommand command) request

moveTab = ({count, tab, registryEntry}) ->
  count = -count if registryEntry.command == "moveTabLeft"
  chrome.tabs.getAllInWindow null, (tabs) ->
    pinnedCount = (tabs.filter (tab) -> tab.pinned).length
    minIndex = if tab.pinned then 0 else pinnedCount
    maxIndex = (if tab.pinned then pinnedCount else tabs.length) - 1
    chrome.tabs.move tab.id,
      index: Math.max minIndex, Math.min maxIndex, tab.index + count

# Start action functions

# These are commands which are bound to keystroke which must be handled by the background page. They are
# mapped in commands.coffee.
BackgroundCommands =
  createTab: repeatCommand (request, callback) ->
    request.url ?= do ->
      url = Settings.get "newTabUrl"
      if url == "pages/blank.html"
        # "pages/blank.html" does not work in incognito mode, so fall back to "chrome://newtab" instead.
        if request.tab.incognito then "chrome://newtab" else chrome.runtime.getURL newTabUrl
      else
        url
    TabOperations.openUrlInNewTab request, (tab) -> callback extend request, {tab, tabId: tab.id}
  duplicateTab: repeatCommand (request, callback) ->
    chrome.tabs.duplicate request.tabId, (tab) -> callback extend request, {tab, tabId: tab.id}
  moveTabToNewWindow: ({count, tab}) ->
    chrome.tabs.query {currentWindow: true}, (tabs) ->
      activeTabIndex = tab.index
      startTabIndex = Math.max 0, Math.min activeTabIndex, tabs.length - count
      [ tab, tabs... ] = tabs[startTabIndex...startTabIndex + count]
      chrome.windows.create {tabId: tab.id, incognito: tab.incognito}, (window) ->
        chrome.tabs.move (tab.id for tab in tabs), {windowId: window.id, index: -1}
  nextTab: (request) -> selectTab "next", request
  previousTab: (request) -> selectTab "previous", request
  firstTab: (request) -> selectTab "first", request
  lastTab: (request) -> selectTab "last", request
  removeTab: ({count, tab}) ->
    chrome.tabs.query {currentWindow: true}, (tabs) ->
      activeTabIndex = tab.index
      startTabIndex = Math.max 0, Math.min activeTabIndex, tabs.length - count
      chrome.tabs.remove (tab.id for tab in tabs[startTabIndex...startTabIndex + count])
  restoreTab: repeatCommand (request, callback) -> chrome.sessions.restore null, callback request
  openCopiedUrlInCurrentTab: (request) -> TabOperations.openUrlInCurrentTab extend request, url: Clipboard.paste()
  openCopiedUrlInNewTab: (request) -> @createTab extend request, url: Clipboard.paste()
  togglePinTab: ({tab}) -> chrome.tabs.update tab.id, {pinned: !tab.pinned}
  showHelp: ({tab, frameId}) ->
    chrome.tabs.sendMessage tab.id, {name: "toggleHelpDialog", dialogHtml: helpDialogHtml(), frameId}
  moveTabLeft: moveTab
  moveTabRight: moveTab
  nextFrame: ({count, frameId, tabId}) ->
    frameIdsForTab[tabId] = cycleToFrame frameIdsForTab[tabId], frameId, count
    chrome.tabs.sendMessage tabId, name: "focusFrame", frameId: frameIdsForTab[tabId][0], highlight: true
  closeTabsOnLeft: (request) -> removeTabsRelative "before", request
  closeTabsOnRight: (request) -> removeTabsRelative "after", request
  closeOtherTabs: (request) -> removeTabsRelative "both", request
  visitPreviousTab: ({count, tab}) ->
    tabIds = BgUtils.tabRecency.getTabsByRecency().filter (tabId) -> tabId != tab.id
    if 0 < tabIds.length
      selectSpecificTab id: tabIds[(count-1) % tabIds.length]

# Remove tabs before, after, or either side of the currently active tab
removeTabsRelative = (direction, {tab: activeTab}) ->
  chrome.tabs.query {currentWindow: true}, (tabs) ->
    shouldDelete = switch direction
      when "before"
        (index) -> index < activeTab.index
      when "after"
        (index) -> index > activeTab.index
      when "both"
        (index) -> index != activeTab.index

    chrome.tabs.remove (tab.id for tab in tabs when not tab.pinned and shouldDelete tab.index)

# Selects a tab before or after the currently selected tab.
# - direction: "next", "previous", "first" or "last".
selectTab = (direction, {count, tab}) ->
  chrome.tabs.getAllInWindow null, (tabs) ->
    if 1 < tabs.length
      toSelect =
        switch direction
          when "next"
            (tab.index + count) % tabs.length
          when "previous"
            (tab.index - count + count * tabs.length) % tabs.length
          when "first"
            Math.min tabs.length - 1, count - 1
          when "last"
            Math.max 0, tabs.length - count
      chrome.tabs.update tabs[toSelect].id, selected: true

chrome.tabs.onUpdated.addListener (tabId, changeInfo, tab) ->
  return unless changeInfo.status == "loading" # only do this once per URL change
  cssConf =
    allFrames: true
    code: Settings.get("userDefinedLinkHintCss")
    runAt: "document_start"
  chrome.tabs.insertCSS tabId, cssConf, -> chrome.runtime.lastError

# End action functions

Frames =
  onConnect: (sender, port) ->
    [tabId, frameId] = [sender.tab.id, sender.frameId]
    topFramePortForTab[tabId] = port if frameId == 0
    frameIdsForTab[tabId] ?= []
    frameIdsForTab[tabId].push frameId unless frameId in frameIdsForTab[tabId]
    port.postMessage handler: "registerFrameId", chromeFrameId: frameId

    port.onDisconnect.addListener listener = ->
      # Unregister the frame.  However, we never unregister the main/top frame.  If the tab is navigating to
      # another page, then there'll be a new top frame with the same Id soon.  If the tab is closing, then
      # we tidy up in the chrome.tabs.onRemoved listener.  This elides any dependency on the order in which
      # events happen (e.g. on navigation, a new top frame registers before the old one unregisters).
      if tabId of frameIdsForTab and frameId != 0
        frameIdsForTab[tabId] = frameIdsForTab[tabId].filter (fId) -> fId != frameId

    # Return our onMessage handler for this port.
    (request, port) =>
      this[request.handler] {request, tabId, frameId, port}

  isEnabledForUrl: ({request, tabId, port}) ->
    urlForTab[tabId] = request.url if request.frameIsFocused
    rule = Exclusions.getRule request.url
    enabledState =
      isEnabledForUrl: not rule or 0 < rule.passKeys.length
      passKeys: rule?.passKeys ? ""

    if request.frameIsFocused
      chrome.browserAction.setIcon tabId: tabId, path:
        if not enabledState.isEnabledForUrl
          "icons/browser_action_disabled.png"
        else if 0 < enabledState.passKeys.length
          "icons/browser_action_partial.png"
        else
          "icons/browser_action_enabled.png"

    # Send the response.  The tests require this to be last.
    port.postMessage extend request, enabledState

  domReady: ({tabId, frameId}) ->
    if frameId == 0
      tabLoadedHandlers[tabId]?()
      delete tabLoadedHandlers[tabId]

  initializeTopFrameUIComponents: ({tabId}) ->
    topFramePortForTab[tabId].postMessage handler: "initializeTopFrameUIComponents"

handleFrameFocused = ({tabId, frameId}) ->
  frameIdsForTab[tabId] ?= []
  frameIdsForTab[tabId] = cycleToFrame frameIdsForTab[tabId], frameId
  # Inform all frames that a frame has received the focus.
  chrome.tabs.sendMessage tabId, name: "frameFocused", focusFrameId: frameId

# Rotate through frames to the frame count places after frameId.
cycleToFrame = (frames, frameId, count = 0) ->
  # We can't always track which frame chrome has focussed, but here we learn that it's frameId; so add an
  # additional offset such that we do indeed start from frameId.
  count = (count + Math.max 0, frames.indexOf frameId) % frames.length
  [frames[count..]..., frames[0...count]...]

# Send a message to all frames in the current tab.
sendMessageToFrames = (request, sender) ->
  chrome.tabs.sendMessage sender.tab.id, request.message

# For debugging only. This allows content scripts to log messages to the extension's logging page.
bgLog = (request, sender) ->
  BgUtils.log "#{request.frameId} #{request.message}", sender

# Port handler mapping
portHandlers =
  completions: handleCompletions
  frames: Frames.onConnect.bind Frames

sendRequestHandlers =
  runBackgroundCommand: (request) -> BackgroundCommands[request.registryEntry.command] request
  getCurrentTabUrl: getCurrentTabUrl
  openUrlInNewTab: TabOperations.openUrlInNewTab
  openUrlInIncognito: (request) -> chrome.windows.create incognito: true, url: Utils.convertToUrl request.url
  openUrlInCurrentTab: TabOperations.openUrlInCurrentTab
  openOptionsPageInNewTab: (request) ->
    chrome.tabs.create url: chrome.runtime.getURL("pages/options.html"), index: request.tab.index + 1
  frameFocused: handleFrameFocused
  nextFrame: BackgroundCommands.nextFrame
  copyToClipboard: copyToClipboard
  pasteFromClipboard: pasteFromClipboard
  selectSpecificTab: selectSpecificTab
  createMark: Marks.create.bind(Marks)
  gotoMark: Marks.goto.bind(Marks)
  sendMessageToFrames: sendMessageToFrames
  log: bgLog
  fetchFileContents: (request, sender) -> fetchFileContents request.fileName

# We always remove chrome.storage.local/findModeRawQueryListIncognito on startup.
chrome.storage.local.remove "findModeRawQueryListIncognito"

# Tidy up tab caches when tabs are removed.  Also remove chrome.storage.local/findModeRawQueryListIncognito if
# there are no remaining incognito-mode windows.  Since the common case is that there are none to begin with,
# we first check whether the key is set at all.
chrome.tabs.onRemoved.addListener (tabId) ->
  delete cache[tabId] for cache in [frameIdsForTab, urlForTab, topFramePortForTab]
  chrome.storage.local.get "findModeRawQueryListIncognito", (items) ->
    if items.findModeRawQueryListIncognito
      chrome.windows.getAll null, (windows) ->
        for window in windows
          return if window.incognito
        # There are no remaining incognito-mode tabs, and findModeRawQueryListIncognito is set.
        chrome.storage.local.remove "findModeRawQueryListIncognito"

# Convenience function for development use.
window.runTests = -> open(chrome.runtime.getURL('tests/dom_tests/dom_tests.html'))

#
# Begin initialization.
#

# Show notification on upgrade.
showUpgradeMessage = ->
  # Avoid showing the upgrade notification when previousVersion is undefined, which is the case for new
  # installs.
  Settings.set "previousVersion", currentVersion  unless Settings.get "previousVersion"
  if Utils.compareVersions(currentVersion, Settings.get "previousVersion" ) == 1
    notificationId = "VimiumUpgradeNotification"
    notification =
      type: "basic"
      iconUrl: chrome.runtime.getURL "icons/vimium.png"
      title: "Vimium Upgrade"
      message: "Vimium has been upgraded to version #{currentVersion}. Click here for more information."
      isClickable: true
    if chrome.notifications?.create?
      chrome.notifications.create notificationId, notification, ->
        unless chrome.runtime.lastError
          Settings.set "previousVersion", currentVersion
          chrome.notifications.onClicked.addListener (id) ->
            if id == notificationId
              chrome.tabs.getSelected null, (tab) ->
                TabOperations.openUrlInNewTab {tab, tabId: tab.id, url: "https://github.com/philc/vimium#release-notes"}
    else
      # We need to wait for the user to accept the "notifications" permission.
      chrome.permissions.onAdded.addListener showUpgradeMessage

showUpgradeMessage()

# The install date is shown on the logging page.
chrome.runtime.onInstalled.addListener ({reason}) ->
  unless reason in ["chrome_update", "shared_module_update"]
    chrome.storage.local.set installDate: new Date().toString()

root.TabOperations = TabOperations
root.Frames = Frames

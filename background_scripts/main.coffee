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
portsForTab = {}
root.urlForTab = {}

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

chrome.runtime.onConnect.addListener (port) ->
  if (portHandlers[port.name])
    port.onMessage.addListener portHandlers[port.name] port.sender, port

chrome.runtime.onMessage.addListener((request, sender, sendResponse) ->
  request = extend {count: 1, frameId: sender.frameId}, extend request, tab: sender.tab, tabId: sender.tab.id
  if (sendRequestHandlers[request.handler])
    sendResponse(sendRequestHandlers[request.handler](request, sender))
  # Ensure the sendResponse callback is freed.
  return false)

onURLChange = (details) ->
  chrome.tabs.sendMessage details.tabId, name: "checkEnabledAfterURLChange"

# Re-check whether Vimium is enabled for a frame when the url changes without a reload.
chrome.webNavigation.onHistoryStateUpdated.addListener onURLChange # history.pushState.
chrome.webNavigation.onReferenceFragmentUpdated.addListener onURLChange # Hash changed.

# Retrieves the help dialog HTML template from a file, and populates it with the latest keybindings.
getHelpDialogHtml = ({showUnboundCommands, showCommandNames, customTitle}) ->
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

# Cache "content_scripts/vimium.css" in chrome.storage.local for UI components.
do ->
  req = new XMLHttpRequest()
  req.open "GET", chrome.runtime.getURL("content_scripts/vimium.css"), true # true -> asynchronous.
  req.onload = ->
    {status, responseText} = req
    chrome.storage.local.set vimiumCSSInChromeStorage: responseText if status == 200
  req.send()

TabOperations =
  # Opens the url in the current tab.
  openUrlInCurrentTab: (request) ->
    chrome.tabs.update request.tabId, url: Utils.convertToUrl request.url

  # Opens request.url in new tab and switches to it.
  openUrlInNewTab: (request, callback = (->)) ->
    tabConfig =
      url: Utils.convertToUrl request.url
      index: request.tab.index + 1
      selected: true
      windowId: request.tab.windowId
      openerTabId: request.tab.id
    chrome.tabs.create tabConfig, callback

#
# Selects the tab with the ID specified in request.id
#
selectSpecificTab = (request) ->
  chrome.tabs.get(request.id, (tab) ->
    chrome.windows.update(tab.windowId, { focused: true })
    chrome.tabs.update(request.id, { selected: true }))

moveTab = ({count, tab, registryEntry}) ->
  count = -count if registryEntry.command == "moveTabLeft"
  chrome.tabs.getAllInWindow null, (tabs) ->
    pinnedCount = (tabs.filter (tab) -> tab.pinned).length
    minIndex = if tab.pinned then 0 else pinnedCount
    maxIndex = (if tab.pinned then pinnedCount else tabs.length) - 1
    chrome.tabs.move tab.id,
      index: Math.max minIndex, Math.min maxIndex, tab.index + count

mkRepeatCommand = (command) -> (request) ->
  if 0 < request.count--
    command request, (request) -> (mkRepeatCommand command) request

# These are commands which are bound to keystrokes which must be handled by the background page. They are
# mapped in commands.coffee.
BackgroundCommands =
  createTab: mkRepeatCommand (request, callback) ->
    request.url ?= do ->
      url = Settings.get "newTabUrl"
      if url == "pages/blank.html"
        # "pages/blank.html" does not work in incognito mode, so fall back to "chrome://newtab" instead.
        if request.tab.incognito then "chrome://newtab" else chrome.runtime.getURL newTabUrl
      else
        url
    TabOperations.openUrlInNewTab request, (tab) -> callback extend request, {tab, tabId: tab.id}
  duplicateTab: mkRepeatCommand (request, callback) ->
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
  restoreTab: mkRepeatCommand (request, callback) -> chrome.sessions.restore null, callback request
  openCopiedUrlInCurrentTab: (request) -> TabOperations.openUrlInCurrentTab extend request, url: Clipboard.paste()
  openCopiedUrlInNewTab: (request) -> @createTab extend request, url: Clipboard.paste()
  togglePinTab: ({tab}) -> chrome.tabs.update tab.id, {pinned: !tab.pinned}
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
    shouldDelete =
      switch direction
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
  return unless changeInfo.status == "loading" # Only do this once per URL change.
  cssConf =
    allFrames: true
    code: Settings.get("userDefinedLinkHintCss")
    runAt: "document_start"
  chrome.tabs.insertCSS tabId, cssConf, -> chrome.runtime.lastError

# Symbolic names for the three browser-action icons.
ENABLED_ICON = "icons/browser_action_enabled.png"
DISABLED_ICON = "icons/browser_action_disabled.png"
PARTIAL_ICON = "icons/browser_action_partial.png"

# Convert the three icon PNGs to image data.
iconImageData = {}
for icon in [ENABLED_ICON, DISABLED_ICON, PARTIAL_ICON]
  iconImageData[icon] = {}
  for scale in [19, 38]
    do (icon, scale) ->
      canvas = document.createElement "canvas"
      canvas.width = canvas.height = scale
      # We cannot do the rest of this in the tests.
      unless chrome.areRunningVimiumTests? and chrome.areRunningVimiumTests
        context = canvas.getContext "2d"
        image = new Image
        image.src = icon
        image.onload = ->
          context.drawImage image, 0, 0, scale, scale
          iconImageData[icon][scale] = context.getImageData 0, 0, scale, scale
          document.body.removeChild canvas
        document.body.appendChild canvas

Frames =
  onConnect: (sender, port) ->
    [tabId, frameId] = [sender.tab.id, sender.frameId]
    port.postMessage handler: "registerFrameId", chromeFrameId: frameId

    # Return our onMessage handler for this port.
    (request, port) =>
      this[request.handler] {request, tabId, frameId, port}

  registerFrame: ({tabId, frameId, port}) ->
    frameIdsForTab[tabId].push frameId unless frameId in frameIdsForTab[tabId] ?= []
    (portsForTab[tabId] ?= {})[frameId] = port

  unregisterFrame: ({tabId, frameId}) ->
    if tabId of frameIdsForTab
      frameIdsForTab[tabId] = (fId for fId in frameIdsForTab[tabId] when fId != frameId)
    if tabId of portsForTab
      delete portsForTab[tabId][frameId]
    HintCoordinator.unregisterFrame tabId, frameId

  isEnabledForUrl: ({request, tabId, port}) ->
    urlForTab[tabId] = request.url if request.frameIsFocused
    enabledState = Exclusions.isEnabledForUrl request.url

    if request.frameIsFocused
      chrome.browserAction.setIcon tabId: tabId, imageData: do ->
        enabledStateIcon =
          if not enabledState.isEnabledForUrl
            DISABLED_ICON
          else if 0 < enabledState.passKeys.length
            PARTIAL_ICON
          else
            ENABLED_ICON
        iconImageData[enabledStateIcon]

    port.postMessage extend request, enabledState

  domReady: ({tabId, frameId}) ->
    if frameId == 0
      tabLoadedHandlers[tabId]?()
      delete tabLoadedHandlers[tabId]

  linkHintsMessage: ({request, tabId, frameId}) ->
    HintCoordinator.onMessage tabId, frameId, request

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

HintCoordinator =
  tabState: {}

  onMessage: (tabId, frameId, request) ->
    if request.messageType of this
      this[request.messageType] tabId, frameId, request
    else
      # If there's no handler here, then the message is forwarded to all frames in the sender's tab.
      @sendMessage request.messageType, tabId, request

  # Post a link-hints message to a particular frame's port. We catch errors in case the frame has gone away.
  postMessage: (tabId, frameId, messageType, port, request = {}) ->
    try
      port.postMessage extend request, {handler: "linkHintsMessage", messageType}
    catch
      @unregisterFrame tabId, frameId

  # Post a link-hints message to all participating frames.
  sendMessage: (messageType, tabId, request = {}) ->
    for own frameId, port of @tabState[tabId].ports
      @postMessage tabId, parseInt(frameId), messageType, port, request

  prepareToActivateMode: (tabId, originatingFrameId, {modeIndex, options}) ->
    @tabState[tabId] = {frameIds: frameIdsForTab[tabId][..], hintDescriptors: {}, originatingFrameId, modeIndex}
    @tabState[tabId].ports = extend {}, portsForTab[tabId]
    @sendMessage "getHintDescriptors", tabId, {modeIndex, options}

  # Receive hint descriptors from all frames and activate link-hints mode when we have them all.
  postHintDescriptors: (tabId, frameId, {hintDescriptors}) ->
    if frameId in @tabState[tabId].frameIds
      @tabState[tabId].hintDescriptors[frameId] = hintDescriptors
      @tabState[tabId].frameIds = @tabState[tabId].frameIds.filter (fId) -> fId != frameId
      if @tabState[tabId].frameIds.length == 0
        for own frameId, port of @tabState[tabId].ports
          if frameId of @tabState[tabId].hintDescriptors
            hintDescriptors = extend {}, @tabState[tabId].hintDescriptors
            # We do not send back the frame's own hint descriptors.  This is faster (approx. speedup 3/2) for
            # link-busy sites like reddit.
            delete hintDescriptors[frameId]
            @postMessage tabId, parseInt(frameId), "activateMode", port,
              originatingFrameId: @tabState[tabId].originatingFrameId
              hintDescriptors: hintDescriptors
              modeIndex: @tabState[tabId].modeIndex

  # If an unregistering frame is participating in link-hints mode, then we need to tidy up after it.
  unregisterFrame: (tabId, frameId) ->
    delete @tabState[tabId]?.ports?[frameId]
    # We fake "postHintDescriptors" for an unregistering frame.
    @postHintDescriptors tabId, frameId, hintDescriptors: [] if @tabState[tabId]?.frameIds

# Port handler mapping
portHandlers =
  completions: handleCompletions
  frames: Frames.onConnect.bind Frames

sendRequestHandlers =
  runBackgroundCommand: (request) -> BackgroundCommands[request.registryEntry.command] request
  getHelpDialogHtml: getHelpDialogHtml
  # getCurrentTabUrl is used by the content scripts to get their full URL, because window.location cannot help
  # with Chrome-specific URLs like "view-source:http:..".
  getCurrentTabUrl: ({tab}) -> tab.url
  openUrlInNewTab: (request) -> TabOperations.openUrlInNewTab request
  openUrlInIncognito: (request) -> chrome.windows.create incognito: true, url: Utils.convertToUrl request.url
  openUrlInCurrentTab: TabOperations.openUrlInCurrentTab
  openOptionsPageInNewTab: (request) ->
    chrome.tabs.create url: chrome.runtime.getURL("pages/options.html"), index: request.tab.index + 1
  frameFocused: handleFrameFocused
  nextFrame: BackgroundCommands.nextFrame
  copyToClipboard: Clipboard.copy.bind Clipboard
  pasteFromClipboard: Clipboard.paste.bind Clipboard
  selectSpecificTab: selectSpecificTab
  createMark: Marks.create.bind(Marks)
  gotoMark: Marks.goto.bind(Marks)
  # Send a message to all frames in the current tab.
  sendMessageToFrames: (request, sender) -> chrome.tabs.sendMessage sender.tab.id, request.message
  # For debugging only. This allows content scripts to log messages to the extension's logging page.
  log: ({frameId, message}, sender) -> BgUtils.log "#{frameId} #{message}", sender

# We always remove chrome.storage.local/findModeRawQueryListIncognito on startup.
chrome.storage.local.remove "findModeRawQueryListIncognito"

# Tidy up tab caches when tabs are removed.  Also remove chrome.storage.local/findModeRawQueryListIncognito if
# there are no remaining incognito-mode windows.  Since the common case is that there are none to begin with,
# we first check whether the key is set at all.
chrome.tabs.onRemoved.addListener (tabId) ->
  delete cache[tabId] for cache in [frameIdsForTab, urlForTab, portsForTab, HintCoordinator.tabState]
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
do showUpgradeMessage = ->
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

# The install date is shown on the logging page.
chrome.runtime.onInstalled.addListener ({reason}) ->
  unless reason in ["chrome_update", "shared_module_update"]
    chrome.storage.local.set installDate: new Date().toString()

extend root, {TabOperations, Frames}

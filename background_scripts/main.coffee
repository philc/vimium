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
tabQueue = {} # windowId -> Array
tabInfoMap = {} # tabId -> object with various tab properties
commandKeys = []
focusedFrame = null
frameIdsForTab = {}
root.urlForTab = {}

# Keys are either literal characters, or "named" - for example <a-b> (alt+b), <left> (left arrow) or <f12>
# This regular expression captures two groups: the first is a named key, the second is the remainder of
# the string.
namedKeyRegex = /^(<(?:[amc]-.|(?:[amc]-)?[a-z0-9]{2,5})>)(.*)$/

# Event handlers
selectionChangedHandlers = []
# Note. tabLoadedHandlers handlers is exported for use also by "marks.coffee".
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

handleCompletions = (request, port) ->
  completionHandlers[request.handler] completers[request.name], request, port

chrome.runtime.onConnect.addListener (port, name) ->
  senderTabId = if port.sender.tab then port.sender.tab.id else null
  # If this is a tab we've been waiting to open, execute any "tab loaded" handlers, e.g. to restore
  # the tab's scroll position. Wait until domReady before doing this; otherwise operations like restoring
  # the scroll position will not be possible.
  if (port.name == "domReady" && senderTabId != null)
    if (tabLoadedHandlers[senderTabId])
      toCall = tabLoadedHandlers[senderTabId]
      # Delete first to be sure there's no circular events.
      delete tabLoadedHandlers[senderTabId]
      toCall.call()

  if (portHandlers[port.name])
    port.onMessage.addListener(portHandlers[port.name])

chrome.runtime.onMessage.addListener((request, sender, sendResponse) ->
  if (sendRequestHandlers[request.handler])
    sendResponse(sendRequestHandlers[request.handler](request, sender))
  # Ensure the sendResponse callback is freed.
  return false)

#
# Used by the content scripts to get their full URL. This is needed for URLs like "view-source:http:# .."
# because window.location doesn't know anything about the Chrome-specific "view-source:".
#
getCurrentTabUrl = (request, sender) -> sender.tab.url

#
# Checks the user's preferences in local storage to determine if Vimium is enabled for the given URL, and
# whether any keys should be passed through to the underlying page.
# The source frame also informs us whether or not it has the focus, which allows us to track the URL of the
# active frame.
#
root.isEnabledForUrl = isEnabledForUrl = (request, sender) ->
  urlForTab[sender.tab.id] = request.url if request.frameIsFocused
  rule = Exclusions.getRule(request.url)
  {
    isEnabledForUrl: not rule or rule.passKeys
    passKeys: rule?.passKeys or ""
  }

onURLChange = (details) ->
  chrome.tabs.sendMessage details.tabId, name: "checkEnabledAfterURLChange"

# Re-check whether Vimium is enabled for a frame when the url changes without a reload.
chrome.webNavigation.onHistoryStateUpdated.addListener onURLChange # history.pushState.
chrome.webNavigation.onReferenceFragmentUpdated.addListener onURLChange # Hash changed.

# Retrieves the help dialog HTML template from a file, and populates it with the latest keybindings.
# This is called by options.coffee.
root.helpDialogHtml = (showUnboundCommands, showCommandNames, customTitle) ->
  commandsToKey = {}
  for key of Commands.keyToCommandRegistry
    command = Commands.keyToCommandRegistry[key].command
    commandsToKey[command] = (commandsToKey[command] || []).concat(key)

  dialogHtml = fetchFileContents("pages/help_dialog.html")
  for group of Commands.commandGroups
    dialogHtml = dialogHtml.replace("{{#{group}}}",
        helpDialogHtmlForCommandGroup(group, commandsToKey, Commands.availableCommands,
                                      showUnboundCommands, showCommandNames))
  dialogHtml = dialogHtml.replace("{{version}}", currentVersion)
  dialogHtml = dialogHtml.replace("{{title}}", customTitle || "Help")
  dialogHtml

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

#
# Returns the keys that can complete a valid command given the current key queue.
#
getCompletionKeysRequest = (request, keysToCheck = "") ->
  name: "refreshCompletionKeys"
  commandKeys: commandKeys

TabOperations =
  # Opens the url in the current tab.
  openUrlInCurrentTab: (request, callback = (->)) ->
    chrome.tabs.getSelected null, (tab) ->
      callback = (->) unless typeof callback == "function"
      chrome.tabs.update tab.id, { url: Utils.convertToUrl(request.url) }, callback

  # Opens request.url in new tab and switches to it if request.selected is true.
  openUrlInNewTab: (request, callback = (->)) ->
    chrome.tabs.getSelected null, (tab) ->
      tabConfig =
        url: Utils.convertToUrl request.url
        index: tab.index + 1
        selected: true
        windowId: tab.windowId
      openerTabId: tab.id
      callback = (->) unless typeof callback == "function"
      chrome.tabs.create tabConfig, callback

  openUrlInIncognito: (request, callback = (->)) ->
    callback = (->) unless typeof callback == "function"
    chrome.windows.create {url: Utils.convertToUrl(request.url), incognito: true}, callback

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

chrome.tabs.onSelectionChanged.addListener (tabId, selectionInfo) ->
  if (selectionChangedHandlers.length > 0)
    selectionChangedHandlers.pop().call()

repeatFunction = (func, totalCount, currentCount, frameId) ->
  if (currentCount < totalCount)
    func(
      -> repeatFunction(func, totalCount, currentCount + 1, frameId),
      frameId)

moveTab = (count) ->
  chrome.tabs.getAllInWindow null, (tabs) ->
    pinnedCount = (tabs.filter (tab) -> tab.pinned).length
    chrome.tabs.getSelected null, (tab) ->
      chrome.tabs.move tab.id,
        index: Math.max pinnedCount, Math.min tabs.length - 1, tab.index + count

# Start action functions

# These are commands which are bound to keystroke which must be handled by the background page. They are
# mapped in commands.coffee.
BackgroundCommands =
  createTab: (callback) ->
    chrome.tabs.query { active: true, currentWindow: true }, (tabs) ->
      tab = tabs[0]
      url = Settings.get "newTabUrl"
      if url == "pages/blank.html"
        # "pages/blank.html" does not work in incognito mode, so fall back to "chrome://newtab" instead.
        url = if tab.incognito then "chrome://newtab" else chrome.runtime.getURL url
      TabOperations.openUrlInNewTab { url }, callback
  duplicateTab: (callback) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.duplicate(tab.id)
      selectionChangedHandlers.push(callback))
  moveTabToNewWindow: (callback) ->
    chrome.tabs.query {active: true, currentWindow: true}, (tabs) ->
      tab = tabs[0]
      chrome.windows.create {tabId: tab.id, incognito: tab.incognito}
  nextTab: (count) -> selectTab "next", count
  previousTab: (count) -> selectTab "previous", count
  firstTab: -> selectTab "first"
  lastTab: -> selectTab "last"
  removeTab: (callback) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.remove(tab.id)
      selectionChangedHandlers.push(callback))
  restoreTab: (callback) ->
    # TODO: remove if-else -block when adopted into stable
    if chrome.sessions
      chrome.sessions.restore(null, (restoredSession) ->
          callback() unless chrome.runtime.lastError)
    else
      # TODO(ilya): Should this be getLastFocused instead?
      chrome.windows.getCurrent((window) ->
        return unless (tabQueue[window.id] && tabQueue[window.id].length > 0)
        tabQueueEntry = tabQueue[window.id].pop()
        # Clean out the tabQueue so we don't have unused windows laying about.
        delete tabQueue[window.id] if (tabQueue[window.id].length == 0)

        # We have to chain a few callbacks to set the appropriate scroll position. We can't just wait until the
        # tab is created because the content script is not available during the "loading" state. We need to
        # wait until that's over before we can call setScrollPosition.
        chrome.tabs.create({ url: tabQueueEntry.url, index: tabQueueEntry.positionIndex }, (tab) ->
          tabLoadedHandlers[tab.id] = ->
            chrome.tabs.sendRequest(tab.id,
              name: "setScrollPosition",
              scrollX: tabQueueEntry.scrollX,
              scrollY: tabQueueEntry.scrollY)
          callback()))
  openCopiedUrlInCurrentTab: (request) -> TabOperations.openUrlInCurrentTab({ url: Clipboard.paste() })
  openCopiedUrlInNewTab: (request) -> TabOperations.openUrlInNewTab({ url: Clipboard.paste() })
  togglePinTab: (request) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.update(tab.id, { pinned: !tab.pinned }))
  showHelp: (callback, frameId) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.sendMessage(tab.id,
        { name: "toggleHelpDialog", dialogHtml: helpDialogHtml(), frameId:frameId }))
  moveTabLeft: (count) -> moveTab -count
  moveTabRight: (count) -> moveTab count
  nextFrame: (count,frameId) ->
    chrome.tabs.getSelected null, (tab) ->
      frameIdsForTab[tab.id] = cycleToFrame frameIdsForTab[tab.id], frameId, count
      chrome.tabs.sendMessage tab.id, name: "focusFrame", frameId: frameIdsForTab[tab.id][0], highlight: true
  mainFrame: ->
    chrome.tabs.getSelected null, (tab) ->
      # The front end interprets a frameId of 0 to mean the main/top from.
      chrome.tabs.sendMessage tab.id, name: "focusFrame", frameId: 0, highlight: true

  closeTabsOnLeft: -> removeTabsRelative "before"
  closeTabsOnRight: -> removeTabsRelative "after"
  closeOtherTabs: -> removeTabsRelative "both"

# Remove tabs before, after, or either side of the currently active tab
removeTabsRelative = (direction) ->
  chrome.tabs.query {currentWindow: true}, (tabs) ->
    chrome.tabs.query {currentWindow: true, active: true}, (activeTabs) ->
      activeTabIndex = activeTabs[0].index

      shouldDelete = switch direction
        when "before"
          (index) -> index < activeTabIndex
        when "after"
          (index) -> index > activeTabIndex
        when "both"
          (index) -> index != activeTabIndex

      toRemove = []
      for tab in tabs
        if not tab.pinned and shouldDelete tab.index
          toRemove.push tab.id
      chrome.tabs.remove toRemove

# Selects a tab before or after the currently selected tab.
# - direction: "next", "previous", "first" or "last".
selectTab = (direction, count = 1) ->
  chrome.tabs.getAllInWindow null, (tabs) ->
    return unless tabs.length > 1
    chrome.tabs.getSelected null, (currentTab) ->
      toSelect =
        switch direction
          when "next"
            currentTab.index + count
          when "previous"
            currentTab.index - count
          when "first"
            0
          when "last"
            tabs.length - 1
      # Bring toSelect into the range [0,tabs.length).
      toSelect = (toSelect + tabs.length * Math.abs count) % tabs.length
      chrome.tabs.update tabs[toSelect].id, selected: true

updateOpenTabs = (tab, deleteFrames = false) ->
  # Chrome might reuse the tab ID of a recently removed tab.
  if tabInfoMap[tab.id]?.deletor
    clearTimeout tabInfoMap[tab.id].deletor
  tabInfoMap[tab.id] =
    url: tab.url
    positionIndex: tab.index
    windowId: tab.windowId
    scrollX: null
    scrollY: null
    deletor: null
  # Frames are recreated on refresh
  delete frameIdsForTab[tab.id] if deleteFrames

# Here's how we set the page icon.  The default is "disabled", so if we do nothing else, then we get the
# grey-out disabled icon.  Thereafter, we only set tab-specific icons, so there's no need to update the icon
# when we visit a tab on which Vimium isn't running.
#
# For active tabs, when a frame starts, it requests its active state via isEnabledForUrl.  We also check the
# state every time a frame gets the focus.  In both cases, the frame then updates the tab's icon accordingly.
#
# Exclusion rule changes (from either the options page or the page popup) propagate via the subsequent focus
# change.  In particular, whenever a frame next gets the focus, it requests its new state and sets the icon
# accordingly.
#
setIcon = (request, sender) ->
  path = switch request.icon
    when "enabled" then "icons/browser_action_enabled.png"
    when "partial" then "icons/browser_action_partial.png"
    when "disabled" then "icons/browser_action_disabled.png"
  chrome.browserAction.setIcon tabId: sender.tab.id, path: path

handleUpdateScrollPosition = (request, sender) ->
  # See note regarding sender.tab at unregisterFrame.
  updateScrollPosition sender.tab, request.scrollX, request.scrollY if sender.tab?

updateScrollPosition = (tab, scrollX, scrollY) ->
  tabInfoMap[tab.id].scrollX = scrollX
  tabInfoMap[tab.id].scrollY = scrollY

chrome.tabs.onUpdated.addListener (tabId, changeInfo, tab) ->
  return unless changeInfo.status == "loading" # only do this once per URL change
  cssConf =
    allFrames: true
    code: Settings.get("userDefinedLinkHintCss")
    runAt: "document_start"
  chrome.tabs.insertCSS tabId, cssConf, -> chrome.runtime.lastError
  updateOpenTabs(tab) if changeInfo.url?

chrome.tabs.onAttached.addListener (tabId, attachedInfo) ->
  # We should update all the tabs in the old window and the new window.
  if tabInfoMap[tabId]
    updatePositionsAndWindowsForAllTabsInWindow(tabInfoMap[tabId].windowId)
  updatePositionsAndWindowsForAllTabsInWindow(attachedInfo.newWindowId)

chrome.tabs.onMoved.addListener (tabId, moveInfo) ->
  updatePositionsAndWindowsForAllTabsInWindow(moveInfo.windowId)

chrome.tabs.onRemoved.addListener (tabId) ->
  openTabInfo = tabInfoMap[tabId]
  updatePositionsAndWindowsForAllTabsInWindow(openTabInfo.windowId)

  # If we restore pages that content scripts can't run on, they'll ignore Vimium keystrokes when they
  # reappear. Pretend they never existed and adjust tab indices accordingly. Could possibly expand this into
  # a blacklist in the future.
  unless chrome.sessions
    if (/^(chrome|view-source:)[^:]*:\/\/.*/.test(openTabInfo.url))
      for i of tabQueue[openTabInfo.windowId]
        if (tabQueue[openTabInfo.windowId][i].positionIndex > openTabInfo.positionIndex)
          tabQueue[openTabInfo.windowId][i].positionIndex--
      return

    if (tabQueue[openTabInfo.windowId])
      tabQueue[openTabInfo.windowId].push(openTabInfo)
    else
      tabQueue[openTabInfo.windowId] = [openTabInfo]

  # keep the reference around for a while to wait for the last messages from the closed tab (e.g. for updating
  # scroll position)
  tabInfoMap.deletor = -> delete tabInfoMap[tabId]
  setTimeout tabInfoMap.deletor, 1000
  delete frameIdsForTab[tabId]
  delete urlForTab[tabId]

unless chrome.sessions
  chrome.windows.onRemoved.addListener (windowId) -> delete tabQueue[windowId]

# End action functions

updatePositionsAndWindowsForAllTabsInWindow = (windowId) ->
  chrome.tabs.getAllInWindow(windowId, (tabs) ->
    for tab in tabs
      openTabInfo = tabInfoMap[tab.id]
      if (openTabInfo)
        openTabInfo.positionIndex = tab.index
        openTabInfo.windowId = tab.windowId)

splitByKeys = (key) ->
  returnArray = []
  while key
    if (key.search(namedKeyRegex) == 0)
      returnArray.push RegExp.$1
      key = RegExp.$2
    else
      returnArray.push key[0]
      key = key[1..]
  returnArray

populateCommandKeys = ->
  commandKeys = (splitByKeys key for key of Commands.keyToCommandRegistry)

# Invoked by options.coffee.
root.refreshCompletionKeysAfterMappingSave = ->
  populateCommandKeys()

  sendRequestToAllTabs(getCompletionKeysRequest())

handleKeyDown = (request, port) ->

executeCommand = (request, sender) ->
  {command, count, frameId} = request
  registryEntry = Commands.keyToCommandRegistry[command]
  runCommand = true

  if registryEntry.noRepeat
    count = 1
  else if registryEntry.repeatLimit and count > registryEntry.repeatLimit
    runCommand = confirm """
      You have asked Vimium to perform #{count} repeats of the command:
      #{Commands.availableCommands[registryEntry.command].description}

      Are you sure you want to continue?
    """

  if runCommand
    if not registryEntry.isBackgroundCommand
      chrome.tabs.sendMessage sender.tab.id,
        name: "executePageCommand"
        command: registryEntry.command
        frameId: frameId
        count: count
        registryEntry: registryEntry
    else
      if registryEntry.passCountToFunction
        BackgroundCommands[registryEntry.command](count, frameId)
      else if registryEntry.noRepeat
        BackgroundCommands[registryEntry.command](frameId)
      else
        repeatFunction(BackgroundCommands[registryEntry.command], count, 0, frameId)

#
# Message all tabs. Args should be the arguments hash used by the Chrome sendRequest API.
#
sendRequestToAllTabs = (args) ->
  chrome.windows.getAll({ populate: true }, (windows) ->
    for window in windows
      for tab in window.tabs
        chrome.tabs.sendMessage(tab.id, args, null))

openOptionsPageInNewTab = ->
  chrome.tabs.getSelected(null, (tab) ->
    chrome.tabs.create({ url: chrome.runtime.getURL("pages/options.html"), index: tab.index + 1 }))

registerFrame = (request, sender) ->
  (frameIdsForTab[sender.tab.id] ?= []).push request.frameId

unregisterFrame = (request, sender) ->
  # When a tab is closing, Chrome sometimes passes messages without sender.tab.  Therefore, we guard against
  # this.
  tabId = sender.tab?.id
  return unless tabId?
  if frameIdsForTab[tabId]?
    if request.tab_is_closing
      updateOpenTabs sender.tab, true
    else
      frameIdsForTab[tabId] = frameIdsForTab[tabId].filter (id) -> id != request.frameId

handleFrameFocused = (request, sender) ->
  tabId = sender.tab.id
  # Cycle frameIdsForTab to the focused frame.  However, also ensure that we don't inadvertently register a
  # frame which wasn't previously registered (such as a frameset).
  if frameIdsForTab[tabId]?
    frameIdsForTab[tabId] = cycleToFrame frameIdsForTab[tabId], request.frameId
  # Inform all frames that a frame has received the focus.
  chrome.tabs.sendMessage sender.tab.id,
    name: "frameFocused"
    focusFrameId: request.frameId

# Rotate through frames to the frame count places after frameId.
cycleToFrame = (frames, frameId, count = 0) ->
  frames ||= []
  # We can't always track which frame chrome has focussed, but here we learn that it's frameId; so add an
  # additional offset such that we do indeed start from frameId.
  count = (count + Math.max 0, frames.indexOf frameId) % frames.length
  [frames[count..]..., frames[0...count]...]

# Send a message to all frames in the current tab.
sendMessageToFrames = (request, sender) ->
  chrome.tabs.sendMessage sender.tab.id, request.message

# For debugging only. This allows content scripts to log messages to the background page's console.
bgLog = (request, sender) ->
  console.log "#{sender.tab.id}/#{request.frameId}", request.message

# Port handler mapping
portHandlers =
  keyDown: handleKeyDown,
  completions: handleCompletions

sendRequestHandlers =
  getCompletionKeys: getCompletionKeysRequest
  getCurrentTabUrl: getCurrentTabUrl
  openUrlInNewTab: TabOperations.openUrlInNewTab
  openUrlInIncognito: TabOperations.openUrlInIncognito
  openUrlInCurrentTab: TabOperations.openUrlInCurrentTab
  openOptionsPageInNewTab: openOptionsPageInNewTab
  executeCommand: executeCommand
  registerFrame: registerFrame
  unregisterFrame: unregisterFrame
  frameFocused: handleFrameFocused
  nextFrame: (request) -> BackgroundCommands.nextFrame 1, request.frameId
  updateScrollPosition: handleUpdateScrollPosition
  copyToClipboard: copyToClipboard
  pasteFromClipboard: pasteFromClipboard
  isEnabledForUrl: isEnabledForUrl
  selectSpecificTab: selectSpecificTab
  createMark: Marks.create.bind(Marks)
  gotoMark: Marks.goto.bind(Marks)
  setIcon: setIcon
  sendMessageToFrames: sendMessageToFrames
  log: bgLog

# We always remove chrome.storage.local/findModeRawQueryListIncognito on startup.
chrome.storage.local.remove "findModeRawQueryListIncognito"

# Remove chrome.storage.local/findModeRawQueryListIncognito if there are no remaining incognito-mode windows.
# Since the common case is that there are none to begin with, we first check whether the key is set at all.
chrome.tabs.onRemoved.addListener (tabId) ->
  chrome.storage.local.get "findModeRawQueryListIncognito", (items) ->
    if items.findModeRawQueryListIncognito
      chrome.windows.getAll null, (windows) ->
        for window in windows
          return if window.incognito
        # There are no remaining incognito-mode tabs, and findModeRawQueryListIncognito is set.
        chrome.storage.local.remove "findModeRawQueryListIncognito"

# Tidy up tab caches when tabs are removed.  We cannot rely on unregisterFrame because Chrome does not always
# provide sender.tab there.
# NOTE(smblott) (2015-05-05) This may break restoreTab on legacy Chrome versions, but we'll be moving to
# chrome.sessions support only soon anyway.
chrome.tabs.onRemoved.addListener (tabId) ->
  delete cache[tabId] for cache in [ frameIdsForTab, urlForTab, tabInfoMap ]

# Convenience function for development use.
window.runTests = -> open(chrome.runtime.getURL('tests/dom_tests/dom_tests.html'))

#
# Begin initialization.
#
Commands.clearKeyMappingsAndSetDefaults()

if Settings.has("keyMappings")
  Commands.parseCustomKeyMappings(Settings.get("keyMappings"))

populateCommandKeys()

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
              TabOperations.openUrlInNewTab url: "https://github.com/philc/vimium#release-notes"
    else
      # We need to wait for the user to accept the "notifications" permission.
      chrome.permissions.onAdded.addListener showUpgradeMessage

# Ensure that tabInfoMap is populated when Vimium is installed.
chrome.windows.getAll { populate: true }, (windows) ->
  for window in windows
    for tab in window.tabs
      updateOpenTabs(tab)
      createScrollPositionHandler = ->
        (response) -> updateScrollPosition(tab, response.scrollX, response.scrollY) if response?
      chrome.tabs.sendMessage(tab.id, { name: "getScrollPosition" }, createScrollPositionHandler())

showUpgradeMessage()

root.TabOperations = TabOperations

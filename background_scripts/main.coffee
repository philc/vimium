root = exports ? window

currentVersion = Utils.getCurrentVersion()

tabQueue = {} # windowId -> Array
tabInfoMap = {} # tabId -> object with various tab properties
keyQueue = "" # Queue of keys typed
validFirstKeys = {}
singleKeyCommands = []
focusedFrame = null
frameIdsForTab = {}

# Keys are either literal characters, or "named" - for example <a-b> (alt+b), <left> (left arrow) or <f12>
# This regular expression captures two groups: the first is a named key, the second is the remainder of
# the string.
namedKeyRegex = /^(<(?:[amc]-.|(?:[amc]-)?[a-z0-9]{2,5})>)(.*)$/

# Event handlers
selectionChangedHandlers = []
tabLoadedHandlers = {} # tabId -> function()

completionSources =
  bookmarks: new BookmarkCompleter()
  history: new HistoryCompleter()
  domains: new DomainCompleter()
  tabs: new TabCompleter()
  seachEngines: new SearchEngineCompleter()

completers =
  omni: new MultiCompleter([
    completionSources.seachEngines,
    completionSources.bookmarks,
    completionSources.history,
    completionSources.domains])
  bookmarks: new MultiCompleter([completionSources.bookmarks])
  tabs: new MultiCompleter([completionSources.tabs])

chrome.runtime.onConnect.addListener((port, name) ->
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

    # domReady is the appropriate time to show the "vimium has been upgraded" message.
    # TODO: This might be broken on pages with frames.
    if (shouldShowUpgradeMessage())
      chrome.tabs.sendMessage(senderTabId, { name: "showUpgradeNotification", version: currentVersion })

  if (portHandlers[port.name])
    port.onMessage.addListener(portHandlers[port.name])
)

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
#
root.isEnabledForUrl = isEnabledForUrl = (request) ->
  rule = Exclusions.getRule(request.url)
  {
    rule: rule
    isEnabledForUrl: not rule or rule.passKeys
    passKeys: rule?.passKeys or ""
  }

# Called by the popup UI.
# If the URL pattern matches an existing rule, then the existing rule is updated. Otherwise, a new rule is created.
root.addExclusionRule = (pattern,passKeys) ->
  if pattern = pattern.trim()
    Exclusions.updateOrAdd({ pattern: pattern, passKeys: passKeys })
    chrome.tabs.query({ windowId: chrome.windows.WINDOW_ID_CURRENT, active: true },
      (tabs) -> updateActiveState(tabs[0].id))

# Called by the popup UI.  Remove all existing exclusion rules with this pattern.
root.removeExclusionRule = (pattern) ->
  if pattern = pattern.trim()
    Exclusions.remove(pattern)
    chrome.tabs.query({ windowId: chrome.windows.WINDOW_ID_CURRENT, active: true },
      (tabs) -> updateActiveState(tabs[0].id))

saveHelpDialogSettings = (request) ->
  Settings.set("helpDialog_showAdvancedCommands", request.showAdvancedCommands)

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
      html.push(
        "<tr class='vimiumReset #{"advanced" if isAdvanced}'>",
        "<td class='vimiumReset'>", Utils.escapeHtml(bindings), "</td>",
        "<td class='vimiumReset'>:</td><td class='vimiumReset'>", availableCommands[command].description)

      if (showCommandNames)
        html.push("<span class='vimiumReset commandName'>(#{command})</span>")

      html.push("</td></tr>")
  html.join("\n")

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
  completionKeys: generateCompletionKeys(keysToCheck)
  validFirstKeys: validFirstKeys

#
# Opens the url in the current tab.
#
openUrlInCurrentTab = (request) ->
  chrome.tabs.getSelected(null,
    (tab) -> chrome.tabs.update(tab.id, { url: Utils.convertToUrl(request.url) }))

#
# Opens request.url in new tab and switches to it if request.selected is true.
#
openUrlInNewTab = (request) ->
  chrome.tabs.getSelected(null, (tab) ->
    chrome.tabs.create({ url: Utils.convertToUrl(request.url), index: tab.index + 1, selected: true }))

openUrlInIncognito = (request) ->
  chrome.windows.create({ url: Utils.convertToUrl(request.url), incognito: true})

#
# Called when the user has clicked the close icon on the "Vimium has been updated" message.
# We should now dismiss that message in all tabs.
#
upgradeNotificationClosed = (request) ->
  Settings.set("previousVersion", currentVersion)
  sendRequestToAllTabs({ name: "hideUpgradeNotification" })

#
# Copies some data (request.data) to the clipboard.
#
copyToClipboard = (request) -> Clipboard.copy(request.data)

#
# Selects the tab with the ID specified in request.id
#
selectSpecificTab = (request) ->
  chrome.tabs.get(request.id, (tab) ->
    chrome.windows.update(tab.windowId, { focused: true })
    chrome.tabs.update(request.id, { selected: true }))

#
# Used by the content scripts to get settings from the local storage.
#
handleSettings = (args, port) ->
  if (args.operation == "get")
    value = Settings.get(args.key)
    port.postMessage({ key: args.key, value: value })
  else # operation == "set"
    Settings.set(args.key, args.value)

refreshCompleter = (request) -> completers[request.name].refresh()

whitespaceRegexp = /\s+/
filterCompleter = (args, port) ->
  queryTerms = if (args.query == "") then [] else args.query.split(whitespaceRegexp)
  completers[args.name].filter(queryTerms, (results) -> port.postMessage({ id: args.id, results: results }))

getCurrentTimeInSeconds = -> Math.floor((new Date()).getTime() / 1000)

chrome.tabs.onSelectionChanged.addListener (tabId, selectionInfo) ->
  if (selectionChangedHandlers.length > 0)
    selectionChangedHandlers.pop().call()

repeatFunction = (func, totalCount, currentCount, frameId) ->
  if (currentCount < totalCount)
    func(
      -> repeatFunction(func, totalCount, currentCount + 1, frameId),
      frameId)

moveTab = (callback, direction) ->
  chrome.tabs.getSelected(null, (tab) ->
    # Use Math.max to prevent -1 as the new index, otherwise the tab of index n will wrap to the far RHS when
    # moved left by exactly (n+1) places.
    chrome.tabs.move(tab.id, {index: Math.max(0, tab.index + direction) }, callback))

# Start action functions

# These are commands which are bound to keystroke which must be handled by the background page. They are
# mapped in commands.coffee.
BackgroundCommands =
  createTab: (callback) -> chrome.tabs.create({url: Settings.get("newTabUrl")}, (tab) -> callback())
  duplicateTab: (callback) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.duplicate(tab.id)
      selectionChangedHandlers.push(callback))
  moveTabToNewWindow: (callback) ->
    chrome.tabs.query {active: true, currentWindow: true}, (tabs) ->
      tab = tabs[0]
      chrome.windows.create {tabId: tab.id, incognito: tab.incognito}
  nextTab: (callback) -> selectTab(callback, "next")
  previousTab: (callback) -> selectTab(callback, "previous")
  firstTab: (callback) -> selectTab(callback, "first")
  lastTab: (callback) -> selectTab(callback, "last")
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
  openCopiedUrlInCurrentTab: (request) -> openUrlInCurrentTab({ url: Clipboard.paste() })
  openCopiedUrlInNewTab: (request) -> openUrlInNewTab({ url: Clipboard.paste() })
  togglePinTab: (request) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.update(tab.id, { pinned: !tab.pinned }))
  showHelp: (callback, frameId) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.sendMessage(tab.id,
        { name: "toggleHelpDialog", dialogHtml: helpDialogHtml(), frameId:frameId }))
  moveTabLeft: (count) -> moveTab(null, -count)
  moveTabRight: (count) -> moveTab(null, count)
  nextFrame: (count,frameId) ->
    chrome.tabs.getSelected(null, (tab) ->
      frames = frameIdsForTab[tab.id]
      # We can't always track which frame chrome has focussed, but here we learn that it's frameId; so add an
      # additional offset such that we do indeed start from frameId.
      count = (count + Math.max 0, frameIdsForTab[tab.id].indexOf frameId) % frames.length
      frames = frameIdsForTab[tab.id] = [frames[count..]..., frames[0...count]...]
      chrome.tabs.sendMessage(tab.id, { name: "focusFrame", frameId: frames[0], highlight: true }))

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
selectTab = (callback, direction) ->
  chrome.tabs.getAllInWindow(null, (tabs) ->
    return unless tabs.length > 1
    chrome.tabs.getSelected(null, (currentTab) ->
      switch direction
        when "next"
          toSelect = tabs[(currentTab.index + 1 + tabs.length) % tabs.length]
        when "previous"
          toSelect = tabs[(currentTab.index - 1 + tabs.length) % tabs.length]
        when "first"
          toSelect = tabs[0]
        when "last"
          toSelect = tabs[tabs.length - 1]
      selectionChangedHandlers.push(callback)
      chrome.tabs.update(toSelect.id, { selected: true })))

updateOpenTabs = (tab) ->
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
  delete frameIdsForTab[tab.id]

setBrowserActionIcon = (tabId,path) ->
  chrome.browserAction.setIcon({ tabId: tabId, path: path })

# Updates the browserAction icon to indicate whether Vimium is enabled or disabled on the current page.
# Also propagates new enabled/disabled/passkeys state to active window, if necessary.
# This lets you disable Vimium on a page without needing to reload.
updateActiveState = (tabId) ->
  enabledIcon = "icons/browser_action_enabled.png"
  disabledIcon = "icons/browser_action_disabled.png"
  partialIcon = "icons/browser_action_partial.png"
  chrome.tabs.get tabId, (tab) ->
    chrome.tabs.sendMessage tabId, { name: "getActiveState" }, (response) ->
      if response
        isCurrentlyEnabled = response.enabled
        currentPasskeys = response.passKeys
        config = isEnabledForUrl({url: tab.url})
        enabled = config.isEnabledForUrl
        passKeys = config.passKeys
        if (enabled and passKeys)
          setBrowserActionIcon(tabId,partialIcon)
        else if (enabled)
          setBrowserActionIcon(tabId,enabledIcon)
        else
          setBrowserActionIcon(tabId,disabledIcon)
        # Propagate the new state only if it has changed.
        if (isCurrentlyEnabled != enabled || currentPasskeys != passKeys)
          chrome.tabs.sendMessage(tabId, { name: "setState", enabled: enabled, passKeys: passKeys })
      else
        # We didn't get a response from the front end, so Vimium isn't running.
        setBrowserActionIcon(tabId,disabledIcon)

handleUpdateScrollPosition = (request, sender) ->
  updateScrollPosition(sender.tab, request.scrollX, request.scrollY)

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
  updateActiveState(tabId)

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

chrome.tabs.onActiveChanged.addListener (tabId, selectInfo) -> updateActiveState(tabId)

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

splitKeyIntoFirstAndSecond = (key) ->
  if (key.search(namedKeyRegex) == 0)
    { first: RegExp.$1, second: RegExp.$2 }
  else
    { first: key[0], second: key.slice(1) }

getActualKeyStrokeLength = (key) ->
  if (key.search(namedKeyRegex) == 0)
    1 + getActualKeyStrokeLength(RegExp.$2)
  else
    key.length

populateValidFirstKeys = ->
  for key of Commands.keyToCommandRegistry
    if (getActualKeyStrokeLength(key) == 2)
      validFirstKeys[splitKeyIntoFirstAndSecond(key).first] = true

populateSingleKeyCommands = ->
  for key of Commands.keyToCommandRegistry
    if (getActualKeyStrokeLength(key) == 1)
      singleKeyCommands.push(key)

# Invoked by options.coffee.
root.refreshCompletionKeysAfterMappingSave = ->
  validFirstKeys = {}
  singleKeyCommands = []

  populateValidFirstKeys()
  populateSingleKeyCommands()

  sendRequestToAllTabs(getCompletionKeysRequest())

# Generates a list of keys that can complete a valid command given the current key queue or the one passed in
generateCompletionKeys = (keysToCheck) ->
  splitHash = splitKeyQueue(keysToCheck || keyQueue)
  command = splitHash.command
  count = splitHash.count

  completionKeys = singleKeyCommands.slice(0)

  if (getActualKeyStrokeLength(command) == 1)
    for key of Commands.keyToCommandRegistry
      splitKey = splitKeyIntoFirstAndSecond(key)
      if (splitKey.first == command)
        completionKeys.push(splitKey.second)

  completionKeys

splitKeyQueue = (queue) ->
  match = /([1-9][0-9]*)?(.*)/.exec(queue)
  count = parseInt(match[1], 10)
  command = match[2]

  { count: count, command: command }

handleKeyDown = (request, port) ->
  key = request.keyChar
  if (key == "<ESC>")
    console.log("clearing keyQueue")
    keyQueue = ""
  else
    console.log("checking keyQueue: [", keyQueue + key, "]")
    keyQueue = checkKeyQueue(keyQueue + key, port.sender.tab.id, request.frameId)
    console.log("new KeyQueue: " + keyQueue)
  # Tell the content script whether there are keys in the queue.
  # FIXME: There is a race condition here.  The behaviour in the content script depends upon whether this message gets
  # back there before or after the next keystroke.
  # That being said, I suspect there are other similar race conditions here, for example in checkKeyQueue().
  # Steve (23 Aug, 14).
  chrome.tabs.sendMessage(port.sender.tab.id,
    name: "currentKeyQueue",
    keyQueue: keyQueue)

checkKeyQueue = (keysToCheck, tabId, frameId) ->
  refreshedCompletionKeys = false
  splitHash = splitKeyQueue(keysToCheck)
  command = splitHash.command
  count = splitHash.count

  return keysToCheck if command.length == 0
  count = 1 if isNaN(count)

  if (Commands.keyToCommandRegistry[command])
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
        chrome.tabs.sendMessage(tabId,
          name: "executePageCommand",
          command: registryEntry.command,
          frameId: frameId,
          count: count,
          passCountToFunction: registryEntry.passCountToFunction,
          completionKeys: generateCompletionKeys(""))
        refreshedCompletionKeys = true
      else
        if registryEntry.passCountToFunction
          BackgroundCommands[registryEntry.command](count, frameId)
        else if registryEntry.noRepeat
          BackgroundCommands[registryEntry.command](frameId)
        else
          repeatFunction(BackgroundCommands[registryEntry.command], count, 0, frameId)

    newKeyQueue = ""
  else if (getActualKeyStrokeLength(command) > 1)
    splitKey = splitKeyIntoFirstAndSecond(command)

    # The second key might be a valid command by its self.
    if (Commands.keyToCommandRegistry[splitKey.second])
      newKeyQueue = checkKeyQueue(splitKey.second, tabId, frameId)
    else
      newKeyQueue = (if validFirstKeys[splitKey.second] then splitKey.second else "")
  else
    newKeyQueue = (if validFirstKeys[command] then count.toString() + command else "")

  # If we haven't sent the completion keys piggybacked on executePageCommand,
  # send them by themselves.
  unless refreshedCompletionKeys
    chrome.tabs.sendMessage(tabId, getCompletionKeysRequest(null, newKeyQueue), null)

  newKeyQueue

#
# Message all tabs. Args should be the arguments hash used by the Chrome sendRequest API.
#
sendRequestToAllTabs = (args) ->
  chrome.windows.getAll({ populate: true }, (windows) ->
    for window in windows
      for tab in window.tabs
        chrome.tabs.sendMessage(tab.id, args, null))

#
# Returns true if the current extension version is greater than the previously recorded version in
# localStorage, and false otherwise.
#
shouldShowUpgradeMessage = ->
  # Avoid showing the upgrade notification when previousVersion is undefined, which is the case for new
  # installs.
  Settings.set("previousVersion", currentVersion) unless Settings.get("previousVersion")
  Utils.compareVersions(currentVersion, Settings.get("previousVersion")) == 1

openOptionsPageInNewTab = ->
  chrome.tabs.getSelected(null, (tab) ->
    chrome.tabs.create({ url: chrome.runtime.getURL("pages/options.html"), index: tab.index + 1 }))

registerFrame = (request, sender) ->
  (frameIdsForTab[sender.tab.id] ?= []).push request.frameId

unregisterFrame = (request, sender) ->
  tabId = sender.tab.id
  if frameIdsForTab[tabId]?
    if request.tab_is_closing
      updateOpenTabs sender.tab
    else
      frameIdsForTab[tabId] = frameIdsForTab[tabId].filter (id) -> id != request.frameId

handleFrameFocused = (request, sender) ->
  tabId = sender.tab.id
  if frameIdsForTab[tabId]?
    frameIdsForTab[tabId] =
      [request.frameId, (frameIdsForTab[tabId].filter (id) -> id != request.frameId)...]

# Port handler mapping
portHandlers =
  keyDown: handleKeyDown,
  settings: handleSettings,
  filterCompleter: filterCompleter

sendRequestHandlers =
  getCompletionKeys: getCompletionKeysRequest,
  getCurrentTabUrl: getCurrentTabUrl,
  openUrlInNewTab: openUrlInNewTab,
  openUrlInIncognito: openUrlInIncognito,
  openUrlInCurrentTab: openUrlInCurrentTab,
  openOptionsPageInNewTab: openOptionsPageInNewTab,
  registerFrame: registerFrame,
  unregisterFrame: unregisterFrame,
  frameFocused: handleFrameFocused,
  nextFrame: (request) -> BackgroundCommands.nextFrame 1, request.frameId
  upgradeNotificationClosed: upgradeNotificationClosed,
  updateScrollPosition: handleUpdateScrollPosition,
  copyToClipboard: copyToClipboard,
  isEnabledForUrl: isEnabledForUrl,
  saveHelpDialogSettings: saveHelpDialogSettings,
  selectSpecificTab: selectSpecificTab,
  refreshCompleter: refreshCompleter,
  createMark: Marks.create.bind(Marks),
  gotoMark: Marks.goto.bind(Marks)

# Convenience function for development use.
window.runTests = -> open(chrome.runtime.getURL('tests/dom_tests/dom_tests.html'))

#
# Begin initialization.
#
Commands.clearKeyMappingsAndSetDefaults()

if Settings.has("keyMappings")
  Commands.parseCustomKeyMappings(Settings.get("keyMappings"))

populateValidFirstKeys()
populateSingleKeyCommands()
if shouldShowUpgradeMessage()
  sendRequestToAllTabs({ name: "showUpgradeNotification", version: currentVersion })

# Ensure that tabInfoMap is populated when Vimium is installed.
chrome.windows.getAll { populate: true }, (windows) ->
  for window in windows
    for tab in window.tabs
      updateOpenTabs(tab)
      createScrollPositionHandler = ->
        (response) -> updateScrollPosition(tab, response.scrollX, response.scrollY) if response?
      chrome.tabs.sendMessage(tab.id, { name: "getScrollPosition" }, createScrollPositionHandler())

# Start pulling changes from synchronized storage.
Sync.init()

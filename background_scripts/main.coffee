root = exports ? window

currentVersion = Utils.getCurrentVersion()

tabQueue = {} # windowId -> Array
openTabs = {} # tabId -> object with various tab properties
keyQueue = "" # Queue of keys typed
validFirstKeys = {}
singleKeyCommands = []
focusedFrame = null
framesForTab = {}

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

completers =
  omni: new MultiCompleter([
    completionSources.bookmarks,
    completionSources.history,
    completionSources.domains])
  bookmarks: new MultiCompleter([completionSources.bookmarks])
  tabs: new MultiCompleter([completionSources.tabs])

chrome.extension.onConnect.addListener((port, name) ->
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
      chrome.tabs.sendRequest(senderTabId, { name: "showUpgradeNotification", version: currentVersion })

  if (portHandlers[port.name])
    port.onMessage.addListener(portHandlers[port.name])
)

chrome.extension.onRequest.addListener((request, sender, sendResponse) ->
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
# Checks the user's preferences in local storage to determine if Vimium is enabled for the given URL.
#
isEnabledForUrl = (request) ->
  # excludedUrls are stored as a series of URL expressions separated by newlines.
  excludedUrls = Settings.get("excludedUrls").split("\n")
  for url in excludedUrls
    parse = url.trim().split(/\s+/)
    url = parse[0]
    passkeys = parse[1..].join("")
    # The user can add "*" to the URL which means ".*"
    regexp = new RegExp("^" + url.replace(/\*/g, ".*") + "$")
    if request.url.match(regexp)
      # exclusion or passkeys is decided on the first pattern matching the request.url
      if passkeys
        # if passkeys are defined, then vimium is enabled, but the indicated keys are passed through to the undelying page
        console.log "isEnabledForUrl: true #{passkeys} #{request.url}"
        return { isEnabledForUrl: true, passkeys: passkeys }
      else
        # otherwise, vimium is disabled
        console.log "isEnabledForUrl: false #{request.url}"
        return { isEnabledForUrl: false }
  # default to "enabled"
  console.log "isEnabledForUrl: true #{request.url}"
  { isEnabledForUrl: true }

# Called by the popup UI. Strips leading/trailing whitespace and ignores empty strings.
root.addExcludedUrl = (url) ->
  return unless url = url.trim()

  excludedUrls = Settings.get("excludedUrls")
  excludedUrls += "\n" + url
  Settings.set("excludedUrls", excludedUrls)

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

  dialogHtml = fetchFileContents("help_dialog.html")
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
  req.open("GET", chrome.extension.getURL(extensionFileName), false) # false => synchronous
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
selectSpecificTab = (request) -> chrome.tabs.update(request.id, { selected: true })

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

filterCompleter = (args, port) ->
  queryTerms = if (args.query == "") then [] else args.query.split(" ")
  completers[args.name].filter(queryTerms, (results) -> port.postMessage({ id: args.id, results: results }))

getCurrentTimeInSeconds = -> Math.floor((new Date()).getTime() / 1000)

chrome.tabs.onSelectionChanged.addListener((tabId, selectionInfo) ->
  if (selectionChangedHandlers.length > 0)
    selectionChangedHandlers.pop().call())

repeatFunction = (func, totalCount, currentCount, frameId) ->
  if (currentCount < totalCount)
    func(
      -> repeatFunction(func, totalCount, currentCount + 1, frameId),
      frameId)

# Start action functions

# These are commands which are bound to keystroke which must be handled by the background page. They are
# mapped in commands.coffee.
BackgroundCommands =
  createTab: (callback) -> chrome.tabs.create({ url: "chrome://newtab" }, (tab) -> callback())
  nextTab: (callback) -> selectTab(callback, "next")
  previousTab: (callback) -> selectTab(callback, "previous")
  firstTab: (callback) -> selectTab(callback, "first")
  lastTab: (callback) -> selectTab(callback, "last")
  removeTab: (callback) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.remove(tab.id)
      # We can't just call the callback here because we need to wait
      # for the selection to change to consider this action done.
      selectionChangedHandlers.push(callback))
  restoreTab: (callback) ->
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
          scrollPort = chrome.tabs.sendRequest(tab.id,
            name: "setScrollPosition",
            scrollX: tabQueueEntry.scrollX,
            scrollY: tabQueueEntry.scrollY)
        callback()))
  openCopiedUrlInCurrentTab: (request) -> openUrlInCurrentTab({ url: Clipboard.paste() })
  openCopiedUrlInNewTab: (request) -> openUrlInNewTab({ url: Clipboard.paste() })
  showHelp: (callback, frameId) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.sendRequest(tab.id,
        { name: "toggleHelpDialog", dialogHtml: helpDialogHtml(), frameId:frameId }))
  nextFrame: (count) ->
    chrome.tabs.getSelected(null, (tab) ->
      frames = framesForTab[tab.id].frames
      currIndex = getCurrFrameIndex(frames)

      # TODO: Skip the "top" frame (which doesn't actually have a <frame> tag),
      # since it exists only to contain the other frames.
      newIndex = (currIndex + count) % frames.length

      chrome.tabs.sendRequest(tab.id, { name: "focusFrame", frameId: frames[newIndex].id, highlight: true }))

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
  openTabs[tab.id] = { url: tab.url, positionIndex: tab.index, windowId: tab.windowId }
  # Frames are recreated on refresh
  delete framesForTab[tab.id]

# Updates the browserAction icon to indicated whether Vimium is enabled or disabled on the current page.
# Also disables Vimium if it is currently enabled but should be disabled according to the url blacklist.
# This lets you disable Vimium on a page without needing to reload.
#
# Three situations are considered:
# 1. Active tab is disabled -> disable icon
# 2. Active tab is enabled and should be enabled -> enable icon
# 3. Active tab is enabled but should be disabled -> disable icon and disable vimium
updateActiveState = (tabId) ->
  enabledIcon = "icons/browser_action_enabled.png"
  disabledIcon = "icons/browser_action_disabled.png"
  chrome.tabs.get(tabId, (tab) ->
    # Default to disabled state in case we can't connect to Vimium, primarily for the "New Tab" page.
    chrome.browserAction.setIcon({ path: disabledIcon })
    chrome.tabs.sendRequest(tabId, { name: "getActiveState" }, (response) ->
      isCurrentlyEnabled = (response? && response.enabled)
      shouldBeEnabled = isEnabledForUrl({url: tab.url}).isEnabledForUrl

      if (isCurrentlyEnabled)
        if (shouldBeEnabled)
          chrome.browserAction.setIcon({ path: enabledIcon })
        else
          chrome.browserAction.setIcon({ path: disabledIcon })
          chrome.tabs.sendRequest(tabId, { name: "disableVimium" })
      else
        chrome.browserAction.setIcon({ path: disabledIcon })))

handleUpdateScrollPosition = (request, sender) ->
  updateScrollPosition(sender.tab, request.scrollX, request.scrollY)

updateScrollPosition = (tab, scrollX, scrollY) ->
  openTabs[tab.id].scrollX = scrollX
  openTabs[tab.id].scrollY = scrollY

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) ->
  return unless changeInfo.status == "loading" # only do this once per URL change
  chrome.tabs.insertCSS tabId,
    allFrames: true
    code: Settings.get("userDefinedLinkHintCss")
    runAt: "document_start"
  updateOpenTabs(tab)
  updateActiveState(tabId))

chrome.tabs.onAttached.addListener((tabId, attachedInfo) ->
  # We should update all the tabs in the old window and the new window.
  if openTabs[tabId]
    updatePositionsAndWindowsForAllTabsInWindow(openTabs[tabId].windowId)
  updatePositionsAndWindowsForAllTabsInWindow(attachedInfo.newWindowId))

chrome.tabs.onMoved.addListener((tabId, moveInfo) ->
  updatePositionsAndWindowsForAllTabsInWindow(moveInfo.windowId))

chrome.tabs.onRemoved.addListener((tabId) ->
  openTabInfo = openTabs[tabId]
  updatePositionsAndWindowsForAllTabsInWindow(openTabInfo.windowId)

  # If we restore chrome:# pages, they'll ignore Vimium keystrokes when they reappear.
  # Pretend they never existed and adjust tab indices accordingly.
  # Could possibly expand this into a blacklist in the future
  if (/^chrome[^:]*:\/\/.*/.test(openTabInfo.url))
    for i of tabQueue[openTabInfo.windowId]
      if (tabQueue[openTabInfo.windowId][i].positionIndex > openTabInfo.positionIndex)
        tabQueue[openTabInfo.windowId][i].positionIndex--
    return

  if (tabQueue[openTabInfo.windowId])
    tabQueue[openTabInfo.windowId].push(openTabInfo)
  else
    tabQueue[openTabInfo.windowId] = [openTabInfo]

  delete openTabs[tabId]
  delete framesForTab[tabId])

chrome.tabs.onActiveChanged.addListener((tabId, selectInfo) -> updateActiveState(tabId))

chrome.windows.onRemoved.addListener((windowId) -> delete tabQueue[windowId])

# End action functions

updatePositionsAndWindowsForAllTabsInWindow = (windowId) ->
  chrome.tabs.getAllInWindow(windowId, (tabs) ->
    for tab in tabs
      openTabInfo = openTabs[tab.id]
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

checkKeyQueue = (keysToCheck, tabId, frameId) ->
  refreshedCompletionKeys = false
  splitHash = splitKeyQueue(keysToCheck)
  command = splitHash.command
  count = splitHash.count

  return keysToCheck if command.length == 0
  count = 1 if isNaN(count)

  if (Commands.keyToCommandRegistry[command])
    registryEntry = Commands.keyToCommandRegistry[command]

    if !registryEntry.isBackgroundCommand
      chrome.tabs.sendRequest(tabId,
        name: "executePageCommand",
        command: registryEntry.command,
        frameId: frameId,
        count: count,
        passCountToFunction: registryEntry.passCountToFunction,
        completionKeys: generateCompletionKeys(""))
      refreshedCompletionKeys = true
    else
      if registryEntry.passCountToFunction
        BackgroundCommands[registryEntry.command](count)
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
    chrome.tabs.sendRequest(tabId, getCompletionKeysRequest(null, newKeyQueue), null)

  newKeyQueue

#
# Message all tabs. Args should be the arguments hash used by the Chrome sendRequest API.
#
sendRequestToAllTabs = (args) ->
  chrome.windows.getAll({ populate: true }, (windows) ->
    for window in windows
      for tab in window.tabs
        chrome.tabs.sendRequest(tab.id, args, null))

# Compares two version strings (e.g. "1.1" and "1.5") and returns
# -1 if versionA is < versionB, 0 if they're equal, and 1 if versionA is > versionB.
compareVersions = (versionA, versionB) ->
  versionA = versionA.split(".")
  versionB = versionB.split(".")
  for i in [0...(Math.max(versionA.length, versionB.length))]
    a = parseInt(versionA[i] || 0, 10)
    b = parseInt(versionB[i] || 0, 10)
    if (a < b)
      return -1
    else if (a > b)
      return 1
  0

#
# Returns true if the current extension version is greater than the previously recorded version in
# localStorage, and false otherwise.
#
shouldShowUpgradeMessage = ->
  # Avoid showing the upgrade notification when previousVersion is undefined, which is the case for new
  # installs.
  Settings.set("previousVersion", currentVersion) unless Settings.get("previousVersion")
  compareVersions(currentVersion, Settings.get("previousVersion")) == 1

openOptionsPageInNewTab = ->
  chrome.tabs.getSelected(null, (tab) ->
    chrome.tabs.create({ url: chrome.extension.getURL("options/options.html"), index: tab.index + 1 }))

registerFrame = (request, sender) ->
  unless framesForTab[sender.tab.id]
    framesForTab[sender.tab.id] = { frames: [] }

  if (request.is_top)
    focusedFrame = request.frameId
    framesForTab[sender.tab.id].total = request.total

  framesForTab[sender.tab.id].frames.push({ id: request.frameId, area: request.area })

handleFrameFocused = (request, sender) -> focusedFrame = request.frameId

getCurrFrameIndex = (frames) ->
  for i in [0...frames.length]
    return i if frames[i].id == focusedFrame
  frames.length + 1

# Port handler mapping
portHandlers =
  keyDown: handleKeyDown,
  settings: handleSettings,
  filterCompleter: filterCompleter

sendRequestHandlers =
  getCompletionKeys: getCompletionKeysRequest,
  getCurrentTabUrl: getCurrentTabUrl,
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

# Convenience function for development use.
window.runTests = -> open(chrome.extension.getURL('tests/dom_tests/dom_tests.html'))

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

# Ensure that openTabs is populated when Vimium is installed.
chrome.windows.getAll({ populate: true }, (windows) ->
  for window in windows
    for tab in window.tabs
      updateOpenTabs(tab)
      createScrollPositionHandler = ->
        (response) -> updateScrollPosition(tab, response.scrollX, response.scrollY) if response?
      chrome.tabs.sendRequest(tab.id, { name: "getScrollPosition" }, createScrollPositionHandler()))

root = exports ? window

currentVersion = Utils.getCurrentVersion()

tabQueue = {} # windowId -> Array
tabInfoMap = {} # tabId -> object with various tab properties
focusedFrame = null
framesForTab = {}

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
# Checks the user's preferences in local storage to determine if Vimium is enabled for the given URL.
#
isEnabledForUrl = (request) ->
  # excludedUrls are stored as a series of URL expressions separated by newlines.
  excludedUrls = Settings.get("excludedUrls").split("\n")
  isEnabled = true
  for url in excludedUrls
    # The user can add "*" to the URL which means ".*"
    regexp = new RegExp("^" + url.replace(/\*/g, ".*") + "$")
    isEnabled = false if request.url.match(regexp)
  { isEnabledForUrl: isEnabled }

# Called by the popup UI. Strips leading/trailing whitespace and ignores empty strings.
root.addExcludedUrl = (url) ->
  return unless url = url.trim()

  excludedUrls = Settings.get("excludedUrls")
  return if excludedUrls.indexOf(url) >= 0

  excludedUrls += "\n" + url
  Settings.set("excludedUrls", excludedUrls)

  chrome.tabs.query({ windowId: chrome.windows.WINDOW_ID_CURRENT, active: true },
    (tabs) -> updateActiveState(tabs[0].id))

saveHelpDialogSettings = (request) ->
  Settings.set("helpDialog_showAdvancedCommands", request.showAdvancedCommands)

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

#
# Execute background commands from the content scripts
#

executeBackgroundCommand = (response) ->
  if response.passCountToFunction
    BackgroundCommands[response.command](response.count)
  else if response.noRepeat
    BackgroundCommands[response.command]()
  else
    repeatFunction(BackgroundCommands[response.command], response.count, 0)


refreshCompleter = (request) -> completers[request.name].refresh()

whitespaceRegexp = /\s+/
filterCompleter = (args, port) ->
  queryTerms = if (args.query == "") then [] else args.query.split(whitespaceRegexp)
  completers[args.name].filter(queryTerms, (results) -> port.postMessage({ id: args.id, results: results }))

getCurrentTimeInSeconds = -> Math.floor((new Date()).getTime() / 1000)

chrome.tabs.onSelectionChanged.addListener (tabId, selectionInfo) ->
  if (selectionChangedHandlers.length > 0)
    selectionChangedHandlers.pop().call()

repeatFunction = (func, totalCount, currentCount) ->
  if (currentCount < totalCount)
    func(-> repeatFunction(func, totalCount, currentCount + 1))

moveTab = (callback, direction) ->
  chrome.tabs.getSelected(null, (tab) ->
    # Use Math.max to prevent -1 as the new index, otherwise the tab of index n will wrap to the far RHS when
    # moved left by exactly (n+1) places.
    chrome.tabs.move(tab.id, {index: Math.max(0, tab.index + direction) }, callback))

# Start action functions

# These are commands which are bound to keystroke which must be handled by the background page. They are
# mapped in commands.coffee.
BackgroundCommands =
  createTab: (callback) -> chrome.tabs.create({ url: "chrome://newtab" }, (tab) -> callback())
  duplicateTab: (callback) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.duplicate(tab.id)
      selectionChangedHandlers.push(callback))
  moveTabToNewWindow: (callback) ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.windows.create({tabId: tab.id}))
  nextTab: (callback) -> selectTab(callback, "next")
  previousTab: (callback) -> selectTab(callback, "previous")
  firstTab: (callback) -> selectTab(callback, "first")
  lastTab: (callback) -> selectTab(callback, "last")
  removeTab: ->
    chrome.tabs.getSelected(null, (tab) ->
      chrome.tabs.remove(tab.id))
  restoreTab: (callback) ->
    # TODO: remove if-else -block when adopted into stable
    if chrome.sessions
      chrome.sessions.restore(null, (restoredSession) -> callback())
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
  moveTabLeft: (count) -> moveTab(null, -count)
  moveTabRight: (count) -> moveTab(null, count)
  nextFrame: (count) ->
    chrome.tabs.getSelected(null, (tab) ->
      frames = framesForTab[tab.id].frames
      currIndex = getCurrFrameIndex(frames)

      # TODO: Skip the "top" frame (which doesn't actually have a <frame> tag),
      # since it exists only to contain the other frames.
      newIndex = (currIndex + count) % frames.length

      chrome.tabs.sendMessage(tab.id, { name: "focusFrame", frameId: frames[newIndex].id, highlight: true }))

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
    chrome.tabs.sendMessage(tabId, { name: "getActiveState" }, (response) ->
      isCurrentlyEnabled = (response? && response.enabled)
      shouldBeEnabled = isEnabledForUrl({url: tab.url}).isEnabledForUrl

      if (isCurrentlyEnabled)
        if (shouldBeEnabled)
          chrome.browserAction.setIcon({ path: enabledIcon })
        else
          chrome.browserAction.setIcon({ path: disabledIcon })
          chrome.tabs.sendMessage(tabId, { name: "disableVimium" })
      else
        chrome.browserAction.setIcon({ path: disabledIcon })))

handleUpdateScrollPosition = (request, sender) ->
  updateScrollPosition(sender.tab, request.scrollX, request.scrollY)

updateScrollPosition = (tab, scrollX, scrollY) ->
  tabInfoMap[tab.id].scrollX = scrollX
  tabInfoMap[tab.id].scrollY = scrollY

chrome.tabs.onUpdated.addListener (tabId, changeInfo, tab) ->
  return unless changeInfo.status == "loading" # only do this once per URL change
  chrome.tabs.insertCSS tabId,
    allFrames: true
    code: Settings.get("userDefinedLinkHintCss")
    runAt: "document_start"
  updateOpenTabs(tab)
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
  delete framesForTab[tabId]

chrome.tabs.onActiveChanged.addListener (tabId, selectInfo) -> updateActiveState(tabId)

chrome.windows.onRemoved.addListener (windowId) -> delete tabQueue[windowId]

# End action functions

updatePositionsAndWindowsForAllTabsInWindow = (windowId) ->
  chrome.tabs.getAllInWindow(windowId, (tabs) ->
    for tab in tabs
      openTabInfo = tabInfoMap[tab.id]
      if (openTabInfo)
        openTabInfo.positionIndex = tab.index
        openTabInfo.windowId = tab.windowId)

#
# Message all tabs. Args should be the arguments hash used by the Chrome sendRequest API.
#
root.sendRequestToAllTabs = (args) ->
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
  settings: handleSettings,
  filterCompleter: filterCompleter

sendRequestHandlers =
  getCurrentTabUrl: getCurrentTabUrl
  openUrlInNewTab: openUrlInNewTab
  openUrlInIncognito: openUrlInIncognito
  openUrlInCurrentTab: openUrlInCurrentTab
  openOptionsPageInNewTab: openOptionsPageInNewTab
  registerFrame: registerFrame
  frameFocused: handleFrameFocused
  upgradeNotificationClosed: upgradeNotificationClosed
  updateScrollPosition: handleUpdateScrollPosition
  copyToClipboard: copyToClipboard
  isEnabledForUrl: isEnabledForUrl
  saveHelpDialogSettings: saveHelpDialogSettings
  selectSpecificTab: selectSpecificTab
  refreshCompleter: refreshCompleter
  createMark: Marks.create.bind(Marks)
  gotoMark: Marks.goto.bind(Marks)
  executeBackgroundCommand: executeBackgroundCommand

# Convenience function for development use.
window.runTests = -> open(chrome.runtime.getURL('tests/dom_tests/dom_tests.html'))

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

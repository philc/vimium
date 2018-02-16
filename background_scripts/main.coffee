root = exports ? window

# The browser may have tabs already open. We inject the content scripts immediately so that they work straight
# away.
chrome.runtime.onInstalled.addListener ({ reason }) ->
  # See https://developer.chrome.com/extensions/runtime#event-onInstalled
  return if reason in [ "chrome_update", "shared_module_update" ]
  return if Utils.isFirefox()
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

frameIdsForTab = {}
root.portsForTab = {}
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
      # NOTE(smblott): response contains `relevancyFunction` (function) properties which cause postMessage,
      # below, to fail in Firefox. See #2576.  We cannot simply delete these methods, as they're needed
      # elsewhere.  Converting the response to JSON and back is a quick and easy way to sanitize the object.
      response = JSON.parse JSON.stringify response
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

chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
  request = extend {count: 1, frameId: sender.frameId}, extend request, tab: sender.tab, tabId: sender.tab.id
  if sendRequestHandlers[request.handler]
    sendResponse sendRequestHandlers[request.handler] request, sender
  # Ensure that the sendResponse callback is freed.
  false

onURLChange = (details) ->
  chrome.tabs.sendMessage details.tabId, name: "checkEnabledAfterURLChange"

# Re-check whether Vimium is enabled for a frame when the url changes without a reload.
chrome.webNavigation.onHistoryStateUpdated.addListener onURLChange # history.pushState.
chrome.webNavigation.onReferenceFragmentUpdated.addListener onURLChange # Hash changed.

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
      active: true
      windowId: request.tab.windowId
    tabConfig.active = request.active if request.active?
    # Firefox does not support "about:newtab" in chrome.tabs.create.
    delete tabConfig["url"] if tabConfig["url"] == Settings.defaults.newTabUrl

    # Firefox <57 throws an error when openerTabId is used (issue 1238314).
    canUseOpenerTabId = not (Utils.isFirefox() and Utils.compareVersions(Utils.firefoxVersion(), "57") < 0)
    tabConfig.openerTabId = request.tab.id if canUseOpenerTabId

    chrome.tabs.create tabConfig, (tab) ->
      callback extend request, {tab, tabId: tab.id}

  # Opens request.url in new window and switches to it.
  openUrlInNewWindow: (request, callback = (->)) ->
    winConfig =
      url: Utils.convertToUrl request.url
      active: true
    winConfig.active = request.active if request.active?
    # Firefox does not support "about:newtab" in chrome.tabs.create.
    delete winConfig["url"] if winConfig["url"] == Settings.defaults.newTabUrl
    chrome.windows.create winConfig, callback

toggleMuteTab = do ->
  muteTab = (tab) -> chrome.tabs.update tab.id, {muted: !tab.mutedInfo.muted}

  ({tab: currentTab, registryEntry}) ->
    if registryEntry.options.all? or registryEntry.options.other?
      # If there are any audible, unmuted tabs, then we mute them; otherwise we unmute any muted tabs.
      chrome.tabs.query {audible: true}, (tabs) ->
        if registryEntry.options.other?
          tabs = (tab for tab in tabs when tab.id != currentTab.id)
        audibleUnmutedTabs = (tab for tab in tabs when tab.audible and not tab.mutedInfo.muted)
        if 0 < audibleUnmutedTabs.length
          muteTab tab for tab in audibleUnmutedTabs
        else
          muteTab tab for tab in tabs when tab.mutedInfo.muted
    else
      muteTab currentTab

#
# Selects the tab with the ID specified in request.id
#
selectSpecificTab = (request) ->
  chrome.tabs.get(request.id, (tab) ->
    chrome.windows?.update(tab.windowId, { focused: true })
    chrome.tabs.update(request.id, { active: true }))

moveTab = ({count, tab, registryEntry}) ->
  count = -count if registryEntry.command == "moveTabLeft"
  chrome.tabs.query { currentWindow: true }, (tabs) ->
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
  # Create a new tab.  Also, with:
  #     map X createTab http://www.bbc.com/news
  # create a new tab with the given URL.
  createTab: mkRepeatCommand (request, callback) ->
    request.urls ?=
      if request.url
        # If the request contains a URL, then use it.
        [request.url]
      else
        # Otherwise, if we have a registryEntry containing URLs, then use them.
        urlList = (opt for opt in request.registryEntry.optionList when Utils.isUrl opt)
        if 0 < urlList.length
          urlList
        else
          # Otherwise, just create a new tab.
          newTabUrl = Settings.get "newTabUrl"
          if newTabUrl == "pages/blank.html"
            # "pages/blank.html" does not work in incognito mode, so fall back to "chrome://newtab" instead.
            [if request.tab.incognito then "chrome://newtab" else chrome.runtime.getURL newTabUrl]
          else
            [newTabUrl]
    if request.registryEntry.options.incognito or request.registryEntry.options.window
      windowConfig =
        url: request.urls
        incognito: request.registryEntry.options.incognito ? false
      chrome.windows.create windowConfig, -> callback request
    else
      urls = request.urls[..].reverse()
      do openNextUrl = (request) ->
        if 0 < urls.length
          TabOperations.openUrlInNewTab (extend request, {url: urls.pop()}), openNextUrl
        else
          callback request
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
  togglePinTab: ({tab}) -> chrome.tabs.update tab.id, {pinned: !tab.pinned}
  toggleMuteTab: toggleMuteTab
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
  reload: ({count, tabId, registryEntry, tab: {windowId}})->
    bypassCache = registryEntry.options.hard ? false
    chrome.tabs.query {windowId}, (tabs) ->
      position = do ->
        for tab, index in tabs
          return index if tab.id == tabId
      tabs = [tabs[position...]..., tabs[...position]...]
      count = Math.min count, tabs.length
      chrome.tabs.reload tab.id, {bypassCache} for tab in tabs[...count]

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
  chrome.tabs.query { currentWindow: true }, (tabs) ->
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
      chrome.tabs.update tabs[toSelect].id, active: true

chrome.webNavigation.onCommitted.addListener ({tabId, frameId}) ->
  cssConf =
    frameId: frameId
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
    port.onDisconnect.addListener -> Frames.unregisterFrame {tabId, frameId, port}
    port.postMessage handler: "registerFrameId", chromeFrameId: frameId
    (portsForTab[tabId] ?= {})[frameId] = port

    # Return our onMessage handler for this port.
    (request, port) =>
      this[request.handler] {request, tabId, frameId, port, sender}

  registerFrame: ({tabId, frameId, port}) ->
    frameIdsForTab[tabId].push frameId unless frameId in frameIdsForTab[tabId] ?= []

  unregisterFrame: ({tabId, frameId, port}) ->
    # Check that the port trying to unregister the frame hasn't already been replaced by a new frame
    # registering. See #2125.
    registeredPort = portsForTab[tabId]?[frameId]
    if registeredPort == port or not registeredPort
      if tabId of frameIdsForTab
        frameIdsForTab[tabId] = (fId for fId in frameIdsForTab[tabId] when fId != frameId)
      if tabId of portsForTab
        delete portsForTab[tabId][frameId]
    HintCoordinator.unregisterFrame tabId, frameId

  isEnabledForUrl: ({request, tabId, port}) ->
    urlForTab[tabId] = request.url if request.frameIsFocused
    request.isFirefox = Utils.isFirefox() # Update the value for Utils.isFirefox in the frontend.
    enabledState = Exclusions.isEnabledForUrl request.url

    if request.frameIsFocused
      chrome.browserAction.setIcon? tabId: tabId, imageData: do ->
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

  # For debugging only. This allows content scripts to log messages to the extension's logging page.
  log: ({frameId, sender, request: {message}}) -> BgUtils.log "#{frameId} #{message}", sender

handleFrameFocused = ({tabId, frameId}) ->
  frameIdsForTab[tabId] ?= []
  frameIdsForTab[tabId] = cycleToFrame frameIdsForTab[tabId], frameId
  # Inform all frames that a frame has received the focus.
  chrome.tabs.sendMessage tabId, name: "frameFocused", focusFrameId: frameId

# Rotate through frames to the frame count places after frameId.
cycleToFrame = (frames, frameId, count = 0) ->
  # We can't always track which frame chrome has focused, but here we learn that it's frameId; so add an
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

  prepareToActivateMode: (tabId, originatingFrameId, {modeIndex, isVimiumHelpDialog}) ->
    @tabState[tabId] = {frameIds: frameIdsForTab[tabId][..], hintDescriptors: {}, originatingFrameId, modeIndex}
    @tabState[tabId].ports = {}
    frameIdsForTab[tabId].map (frameId) => @tabState[tabId].ports[frameId] = portsForTab[tabId][frameId]
    @sendMessage "getHintDescriptors", tabId, {modeIndex, isVimiumHelpDialog}

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
    if @tabState[tabId]?
      if @tabState[tabId].ports?[frameId]?
        delete @tabState[tabId].ports[frameId]
      if @tabState[tabId].frameIds? and frameId in @tabState[tabId].frameIds
        # We fake an empty "postHintDescriptors" because the frame has gone away.
        @postHintDescriptors tabId, frameId, hintDescriptors: []

# Port handler mapping
portHandlers =
  completions: handleCompletions
  frames: Frames.onConnect.bind Frames

sendRequestHandlers =
  runBackgroundCommand: (request) -> BackgroundCommands[request.registryEntry.command] request
  # getCurrentTabUrl is used by the content scripts to get their full URL, because window.location cannot help
  # with Chrome-specific URLs like "view-source:http:..".
  getCurrentTabUrl: ({tab}) -> tab.url
  openUrlInNewTab: mkRepeatCommand (request, callback) -> TabOperations.openUrlInNewTab request, callback
  openUrlInNewWindow: (request) -> TabOperations.openUrlInNewWindow request
  openUrlInIncognito: (request) -> chrome.windows.create incognito: true, url: Utils.convertToUrl request.url
  openUrlInCurrentTab: TabOperations.openUrlInCurrentTab
  openOptionsPageInNewTab: (request) ->
    chrome.tabs.create url: chrome.runtime.getURL("pages/options.html"), index: request.tab.index + 1
  frameFocused: handleFrameFocused
  nextFrame: BackgroundCommands.nextFrame
  selectSpecificTab: selectSpecificTab
  createMark: Marks.create.bind(Marks)
  gotoMark: Marks.goto.bind(Marks)
  # Send a message to all frames in the current tab.
  sendMessageToFrames: (request, sender) -> chrome.tabs.sendMessage sender.tab.id, request.message

# We always remove chrome.storage.local/findModeRawQueryListIncognito on startup.
chrome.storage.local.remove "findModeRawQueryListIncognito"

# Tidy up tab caches when tabs are removed.  Also remove chrome.storage.local/findModeRawQueryListIncognito if
# there are no remaining incognito-mode windows.  Since the common case is that there are none to begin with,
# we first check whether the key is set at all.
chrome.tabs.onRemoved.addListener (tabId) ->
  delete cache[tabId] for cache in [frameIdsForTab, urlForTab, portsForTab, HintCoordinator.tabState]
  chrome.storage.local.get "findModeRawQueryListIncognito", (items) ->
    if items.findModeRawQueryListIncognito
      chrome.windows?.getAll null, (windows) ->
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
  currentVersion = Utils.getCurrentVersion()
  # Avoid showing the upgrade notification when previousVersion is undefined, which is the case for new
  # installs.
  Settings.set "previousVersion", currentVersion  unless Settings.has "previousVersion"
  previousVersion = Settings.get "previousVersion"
  if Utils.compareVersions(currentVersion, previousVersion ) == 1
    currentVersionNumbers = currentVersion.split "."
    previousVersionNumbers = previousVersion.split "."
    if currentVersionNumbers[...2].join(".") == previousVersionNumbers[...2].join(".")
      # We do not show an upgrade message for patch/silent releases.  Such releases have the same major and
      # minor version numbers.  We do, however, update the recorded previous version.
      Settings.set "previousVersion", currentVersion
    else
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
                chrome.tabs.query { active: true, currentWindow: true }, ([tab]) ->
                  TabOperations.openUrlInNewTab {tab, tabId: tab.id, url: "https://github.com/philc/vimium#release-notes"}
      else
        # We need to wait for the user to accept the "notifications" permission.
        chrome.permissions.onAdded.addListener showUpgradeMessage

# The install date is shown on the logging page.
chrome.runtime.onInstalled.addListener ({reason}) ->
  unless reason in ["chrome_update", "shared_module_update"]
    chrome.storage.local.set installDate: new Date().toString()

extend root, {TabOperations, Frames}

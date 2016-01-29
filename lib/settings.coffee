
# A "setting" is a stored key/value pair.  An "option" is a setting which has a default value and whose value
# can be changed on the options page.
#
# Option values which have never been changed by the user are in Settings.defaults.
#
# Settings whose values have been changed are:
# 1. stored either in chrome.storage.sync or in chrome.storage.local (but never both), and
# 2. cached in Settings.cache; on extension pages, Settings.cache uses localStorage (so it persists).
#
# In all cases except Settings.defaults, values are stored as jsonified strings.

Settings =
  debug: false
  storage: chrome.storage.sync
  cache: {}
  isLoaded: false
  onLoadedCallbacks: []

  init: ->
    if Utils.isExtensionPage()
      # On extension pages, we use localStorage (or a copy of it) as the cache.
      @cache = if Utils.isBackgroundPage() then localStorage else extend {}, localStorage
      @onLoaded()

    chrome.storage.local.get null, (localItems) =>
      localItems = {} if chrome.runtime.lastError
      @storage.get null, (syncedItems) =>
        unless chrome.runtime.lastError
          @handleUpdateFromChromeStorage key, value for own key, value of extend localItems, syncedItems

        chrome.storage.onChanged.addListener (changes, area) =>
          @propagateChangesFromChromeStorage changes if area == "sync"

        @onLoaded()

  # Called after @cache has been initialized.  On extension pages, this will be called twice, but that does
  # not matter because it's idempotent.
  onLoaded: ->
    @log "onLoaded: #{@onLoadedCallbacks.length} callback(s)"
    @isLoaded = true
    callback() while callback = @onLoadedCallbacks.pop()

  shouldSyncKey: (key) ->
    (key of @defaults) and key not in [ "settingsVersion", "previousVersion" ]

  propagateChangesFromChromeStorage: (changes) ->
    @handleUpdateFromChromeStorage key, change?.newValue for own key, change of changes

  handleUpdateFromChromeStorage: (key, value) ->
    @log "handleUpdateFromChromeStorage: #{key}"
    # Note: value here is either null or a JSONified string.  Therefore, even falsy settings values (like
    # false, 0 or "") are truthy here.  Only null is falsy.
    if @shouldSyncKey key
      unless value and key of @cache and @cache[key] == value
        value ?= JSON.stringify @defaults[key]
        @set key, JSON.parse(value), false

  get: (key) ->
    console.log "WARNING: Settings have not loaded yet; using the default value for #{key}." unless @isLoaded
    if key of @cache and @cache[key]? then JSON.parse @cache[key] else @defaults[key]

  set: (key, value, shouldSetInSyncedStorage = true) ->
    @cache[key] = JSON.stringify value
    @log "set: #{key} (length=#{@cache[key].length}, shouldSetInSyncedStorage=#{shouldSetInSyncedStorage})"
    if @shouldSyncKey key
      if shouldSetInSyncedStorage
        setting = {}; setting[key] = @cache[key]
        @log "   chrome.storage.sync.set(#{key})"
        @storage.set setting
      if Utils.isBackgroundPage()
        # Remove options installed by the "copyNonDefaultsToChromeStorage-20150717" migration; see below.
        @log "   chrome.storage.local.remove(#{key})"
        chrome.storage.local.remove key
    @performPostUpdateHook key, value

  clear: (key) ->
    @log "clear: #{key}"
    @set key, @defaults[key]

  has: (key) -> key of @cache

  use: (key, callback) ->
    @log "use: #{key} (isLoaded=#{@isLoaded})"
    invokeCallback = => callback @get key
    if @isLoaded then invokeCallback() else @onLoadedCallbacks.push invokeCallback

  # For settings which require action when their value changes, add hooks to this object.
  postUpdateHooks: {}
  performPostUpdateHook: (key, value) -> @postUpdateHooks[key]? value

  # For development only.
  log: (args...) ->
    console.log "settings:", args... if @debug

  # Default values for all settings.
  defaults:
    scrollStepSize: 60
    smoothScroll: true
    keyMappings: "# Insert your preferred key mappings here."
    linkHintCharacters: "sadfjklewcmpgh"
    linkHintNumbers: "0123456789"
    filterLinkHints: false
    hideHud: false
    userDefinedLinkHintCss:
      """
      div > .vimiumHintMarker {
      /* linkhint boxes */
      background: -webkit-gradient(linear, left top, left bottom, color-stop(0%,#FFF785),
        color-stop(100%,#FFC542));
      border: 1px solid #E3BE23;
      }

      div > .vimiumHintMarker span {
      /* linkhint text */
      color: black;
      font-weight: bold;
      font-size: 12px;
      }

      div > .vimiumHintMarker > .matchingCharacter {
      }
      """
    # Default exclusion rules.
    exclusionRules:
      [
        # Disable Vimium on Gmail.
        { pattern: "https?://mail.google.com/*", passKeys: "" }
      ]

    # NOTE: If a page contains both a single angle-bracket link and a double angle-bracket link, then in
    # most cases the single bracket link will be "prev/next page" and the double bracket link will be
    # "first/last page", so we put the single bracket first in the pattern string so that it gets searched
    # for first.

    # "\bprev\b,\bprevious\b,\bback\b,<,←,«,≪,<<"
    previousPatterns: "prev,previous,back,older,<,\u2190,\xab,\u226a,<<"
    # "\bnext\b,\bmore\b,>,→,»,≫,>>"
    nextPatterns: "next,more,newer,>,\u2192,\xbb,\u226b,>>"
    # default/fall back search engine
    searchUrl: "https://www.google.com/search?q="
    # put in an example search engine
    searchEngines:
      """
      w: http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s Wikipedia

      # More examples.
      #
      # (Vimium supports search completion Wikipedia, as
      # above, and for these.)
      #
      # g: http://www.google.com/search?q=%s Google
      # l: http://www.google.com/search?q=%s&btnI I'm feeling lucky...
      # y: http://www.youtube.com/results?search_query=%s Youtube
      # gm: https://www.google.com/maps?q=%s Google maps
      # b: https://www.bing.com/search?q=%s Bing
      # d: https://duckduckgo.com/?q=%s DuckDuckGo
      # az: http://www.amazon.com/s/?field-keywords=%s Amazon
      # qw: https://www.qwant.com/?q=%s Qwant
      """
    newTabUrl: "chrome://newtab"
    grabBackFocus: false
    regexFindMode: false

    settingsVersion: Utils.getCurrentVersion()
    helpDialog_showAdvancedCommands: false
    optionsPage_showAdvancedOptions: false

Settings.init()

# Perform migration from old settings versions, if this is the background page.
if Utils.isBackgroundPage()

  # We use settingsVersion to coordinate any necessary schema changes.
  if Utils.compareVersions("1.42", Settings.get("settingsVersion")) != -1
    Settings.set("scrollStepSize", parseFloat Settings.get("scrollStepSize"))
  Settings.set("settingsVersion", Utils.getCurrentVersion())

  # Migration (after 1.49, 2015/2/1).
  # Legacy setting: findModeRawQuery (a string).
  # New setting: findModeRawQueryList (a list of strings), now stored in chrome.storage.local (not localStorage).
  chrome.storage.local.get "findModeRawQueryList", (items) ->
    unless chrome.runtime.lastError or items.findModeRawQueryList
      rawQuery = Settings.get "findModeRawQuery"
      chrome.storage.local.set findModeRawQueryList: (if rawQuery then [ rawQuery ] else [])

  # Migration (after 1.51, 2015/6/17).
  # Copy options with non-default values (and which are not in synced storage) to chrome.storage.local;
  # thereby making these settings accessible within content scripts.
  do (migrationKey = "copyNonDefaultsToChromeStorage-20150717") ->
    unless localStorage[migrationKey]
      chrome.storage.sync.get null, (items) ->
        unless chrome.runtime.lastError
          updates = {}
          for own key of localStorage
            if Settings.shouldSyncKey(key) and not items[key]
              updates[key] = localStorage[key]
          chrome.storage.local.set updates, ->
            localStorage[migrationKey] = not chrome.runtime.lastError

root = exports ? window
root.Settings = Settings

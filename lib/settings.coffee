#
# * Sync.set() and Sync.clear() propagate local changes to chrome.storage.sync.
# * Sync.handleStorageUpdate() listens for changes to chrome.storage.sync and propagates those
#   changes to localStorage and into vimium's internal state.
# * Sync.fetchAsync() polls chrome.storage.sync at startup, similarly propagating
#   changes to localStorage and into vimium's internal state.
#
# The effect is best-effort synchronization of vimium options/settings between
# chrome/vimium instances.
#
# NOTE:
#   Values handled within this module are ALWAYS already JSON.stringifed, so
#   they're always non-empty strings.
#

root = exports ? window
Sync =

  storage: chrome.storage.sync
  doNotSync: ["settingsVersion", "previousVersion"]

  # This is called in main.coffee.
  init: ->
    chrome.storage.onChanged.addListener (changes, area) -> Sync.handleStorageUpdate changes, area
    @fetchAsync()

  # Asynchronous fetch from synced storage, called only at startup.
  fetchAsync: ->
    @storage.get null, (items) =>
      unless chrome.runtime.lastError
        for own key, value of items
          Settings.storeAndPropagate key, value if @shouldSyncKey key

  # Asynchronous message from synced storage.
  handleStorageUpdate: (changes, area) ->
    for own key, change of changes
      Settings.storeAndPropagate key, change?.newValue if @shouldSyncKey key

  # Only called synchronously from within vimium, never on a callback.
  # No need to propagate updates to the rest of vimium, that's already been done.
  set: (key, value) ->
    if @shouldSyncKey key
      setting = {}; setting[key] = value
      @storage.set setting

  # Only called synchronously from within vimium, never on a callback.
  clear: (key) ->
    @storage.remove key if @shouldSyncKey key

  # Should we synchronize this key?
  shouldSyncKey: (key) -> key not in @doNotSync

#
# Used by all parts of Vimium to manipulate localStorage.
#

# Select the object to use as the cache for settings.
if Utils.isExtensionPage()
  if Utils.isBackgroundPage()
    settingsCache = localStorage
  else
    settingsCache = extend {}, localStorage # Make a copy of the cached settings from localStorage
else
  settingsCache = {}

root.Settings = Settings =
  cache: settingsCache
  init: -> Sync.init()
  get: (key) ->
    if (key of @cache) then JSON.parse(@cache[key]) else @defaults[key]

  set: (key, value) ->
    # Don't store the value if it is equal to the default, so we can change the defaults in the future
    if (value == @defaults[key])
      @clear(key)
    else
      jsonValue = JSON.stringify value
      @cache[key] = jsonValue
      Sync.set key, jsonValue

  clear: (key) ->
    if @has key
      delete @cache[key]
    Sync.clear key

  has: (key) -> key of @cache

  # For settings which require action when their value changes, add hooks to this object, to be called from
  # options/options.coffee (when the options page is saved), and by Settings.storeAndPropagate (when an
  # update propagates from chrome.storage.sync).
  postUpdateHooks: {}

  # postUpdateHooks convenience wrapper
  performPostUpdateHook: (key, value) ->
    @postUpdateHooks[key]? value

  # Only ever called from asynchronous synced-storage callbacks (fetchAsync and handleStorageUpdate).
  storeAndPropagate: (key, value) ->
    return unless key of @defaults
    return if value and key of @cache and @cache[key] is value
    defaultValue = @defaults[key]
    defaultValueJSON = JSON.stringify(defaultValue)

    if value and value != defaultValueJSON
      # Key/value has been changed to non-default value at remote instance.
      @cache[key] = value
      @performPostUpdateHook key, JSON.parse(value)
    else
      # Key has been reset to default value at remote instance.
      if key of @cache
        delete @cache[key]
      @performPostUpdateHook key, defaultValue

  # options.coffee and options.html only handle booleans and strings; therefore all defaults must be booleans
  # or strings
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
        { pattern: "http*://mail.google.com/*", passKeys: "" }
      ]

    # NOTE: If a page contains both a single angle-bracket link and a double angle-bracket link, then in
    # most cases the single bracket link will be "prev/next page" and the double bracket link will be
    # "first/last page", so we put the single bracket first in the pattern string so that it gets searched
    # for first.

    # "\bprev\b,\bprevious\b,\bback\b,<,←,«,≪,<<"
    previousPatterns: "prev,previous,back,<,\u2190,\xab,\u226a,<<"
    # "\bnext\b,\bmore\b,>,→,»,≫,>>"
    nextPatterns: "next,more,>,\u2192,\xbb,\u226b,>>"
    # default/fall back search engine
    searchUrl: "https://www.google.com/search?q="
    # put in an example search engine
    searchEngines: [
      "w: http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s Wikipedia"
      ""
      "# More examples."
      "#"
      "# (Vimium has built-in completion for these.)"
      "#"
      "# g: http://www.google.com/search?q=%s Google"
      "# l: http://www.google.com/search?q=%s&btnI I'm feeling lucky..."
      "# y: http://www.youtube.com/results?search_query=%s Youtube"
      "# b: https://www.bing.com/search?q=%s Bing"
      "# d: https://duckduckgo.com/?q=%s DuckDuckGo"
      "# az: http://www.amazon.com/s/?field-keywords=%s Amazon"
      "#"
      "# Another example (for Vimium does not have completion)."
      "#"
      "# m: https://www.google.com/maps/search/%s Google Maps"
      ].join "\n"
    newTabUrl: "chrome://newtab"
    grabBackFocus: false

    settingsVersion: Utils.getCurrentVersion()

# Export Sync via Settings for tests.
root.Settings.Sync = Sync

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

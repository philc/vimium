#
# Used by all parts of Vimium to manipulate chrome.storage.
#

if location.protocol == "chrome-extension:" and chrome.extension.getBackgroundPage() == window
  # We're on the background page. Use localStorage, so we don't have to wait before settings are available.
  values = localStorage
else
  values = {}
eventListeners = {}
syncTypeForValuesToLoad = {}

root = exports ? window
root.Settings = Settings =
  init: (valuesToLoad) ->
    if valuesToLoad?
      syncTypeForValuesToLoad[key] = Sync.syncType key for key in valuesToLoad
    else
      syncTypeForValuesToLoad[key] = Sync.syncType key for key of @defaults
    Sync.init()

  get: (key) ->
    if (key of values) then JSON.parse(values[key]) else @defaults[key]

  set: (key, value) ->
    # Don't store the value if it is equal to the default, so we can change the defaults in the future
    if (value == @defaults[key])
      @clear(key)
    else
      jsonValue = JSON.stringify value
      values[key] = jsonValue
      Sync.set key, jsonValue

  clear: (key) ->
    delete values[key]
    Sync.clear key

  has: (key) -> key of values

  # Dispatches the "load" event if both chrome.storage.sync and chrome.storage.local have loaded.
  loaded: do ->
    loaded = {}
    hasLoaded = -> loaded.sync and loaded.local
    (syncType) ->
      return if hasLoaded()
      loaded[syncType] = true
      @dispatchEvent "load" if hasLoaded()

  addEventListener: (eventName, callback) ->
    (eventListeners[eventName] ?= []).push(callback)
  dispatchEvent: (eventName, details) ->
    listener details while (listener = eventListeners[eventName].pop())

  # options.coffee and options.html only handle booleans and strings; therefore all defaults must be booleans
  # or strings
  defaults:
    scrollStepSize: 60
    smoothScroll: true
    keyMappings: "# Insert your prefered key mappings here."
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
    searchUrl: "http://www.google.com/search?q="
    # put in an example search engine
    searchEngines: "w: http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s"
    newTabUrl: "chrome://newtab"

    settingsVersion: Utils.getCurrentVersion()

#
# * Sync.set() and Sync.clear() propagate local changes to chrome.storage.sync.
# * Sync.handleStorageUpdate() listens for changes to chrome.storage.sync and propagates those
#   changes to values and into vimium's internal state.
# * Sync.fetchAsync() polls chrome.storage.sync at startup, similarly propagating
#   changes to values and into vimium's internal state.
#
# Changes are propagated into vimium's state using the same mechanism
# (Settings.dispatchEvent) that is used when options are changed on
# the options page.
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

  # April 19 2014: Leave logging statements in, but disable debugging. We may need to come back to this, so
  # removing logging now would be premature. However, if users report problems, they are unlikely to notice
  # and make sense of console logs on background pages. So disable it, by default. For genuine errors, we
  # call console.log directly.
  debug: false
  doNotSync: ["settingsVersion", "previousVersion"]

  # This is called in main.coffee.
  init: ->
    chrome.storage.onChanged.addListener (changes, area) -> Sync.handleStorageUpdate changes, area

    # Fetch settings asynchronously from chrome.storage.
    chrome.storage.sync.get Object.keys(syncTypeForValuesToLoad), @updateSettings.bind(this, "sync")
    chrome.storage.local.get Object.keys(syncTypeForValuesToLoad), @updateSettings.bind(this, "local")

  updateSettings: (syncType, items) ->
    if chrome.runtime.lastError is undefined
      items_ = {}
      for own key, value of items
        @log "updateSettings: #{key} <- #{value}" if functionName?
        @storeAndPropagate key, value, syncType, items_
      Settings.dispatchEvent "update", items_
      Settings.loaded syncType
      callback?()
    else
      @logError "Sync.updateSettings" if chrome.runtime.lastError

  # Asynchronous message from chrome.storage.
  handleStorageUpdate: (changes, syncType) ->
    return if syncType == "managed"
    items_ = {}
    for own key, {newValue: value} of changes
      @log "handleStorageUpdate: #{key} <- #{value}" if functionName?
      @storeAndPropagate key, value, syncType, items_
    Settings.dispatchEvent "update", items_

  # Only ever called from asynchronous chrome.storage callbacks (fetchAsync and handleStorageUpdate).
  storeAndPropagate: (key, value, syncType, items) ->
    return if syncTypeForValuesToLoad[key] and syncType == @syncType key
    return if value and key of values and values[key] is value

    defaultValue = Settings.defaults[key]
    parsedValue = JSON.parse value
    items?[key] = parsedValue # Add this to the settings that should be mentioned in the "update" event.

    if value and parsedValue != defaultValue
      # Key/value has been changed to non-default value at remote instance.
      @log "storeAndPropagate update: #{key}=#{value}"
      values[key] = value
    else
      # Key has been reset to default value at remote instance.
      @log "storeAndPropagate clear: #{key}"
      delete values[key]

  # Only called synchronously from within vimium, never on a callback.
  # No need to propagate updates to the rest of vimium, that's already been done.
  set: (key, value) ->
    storage = if @syncType key then chrome.storage.sync else chrome.storage.local
    @log "set scheduled: #{key}=#{value}"
    key_value = {}
    key_value[key] = value
    storage.set key_value, =>
      @logError "Sync.set" if chrome.runtime.lastError

  # Only called synchronously from within vimium, never on a callback.
  clear: (key) ->
    storage = chrome.storage[@syncType key]
    @log "clear scheduled: #{key}"
    storage.remove key, =>
      @logError "Sync.clear" if chrome.runtime.lastError

  # Should we synchronize this key?
  syncType: (key) ->
    if key in @doNotSync then "local" else "sync"

  log: (msg) -> console.log "Sync: #{msg}" if @debug

  logError: (functionName) ->
    console.log "callback for #{functionName} indicates error:"
    console.log chrome.runtime.lastError


# We use settingsVersion to coordinate any necessary schema changes.
if Utils.compareVersions("1.42", Settings.get("settingsVersion")) != -1
  Settings.set("scrollStepSize", parseFloat Settings.get("scrollStepSize"))
Settings.set("settingsVersion", Utils.getCurrentVersion())

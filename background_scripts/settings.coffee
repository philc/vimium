#
# Used by all parts of Vimium to manipulate chrome.storage.
#

if location.protocol == "chrome-extension:" and chrome.extension.getBackgroundPage() == window
  # We're on the background page. Use localStorage, so we don't have to wait before settings are available.
  values = localStorage
else
  values = {}
eventListeners = {}
valuesToLoadHash = {}

root = exports ? window
root.Settings = Settings =
  init: (valuesToLoad) ->
    if valuesToLoad?
      valuesToLoadHash[key] = true for key in valuesToLoad
    else
      valuesToLoadHash[key] = true for key of @defaults
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
    syncLoaded = false
    localLoaded = false
    (isSync) ->
      loaded = syncLoaded and localLoaded
      return if loaded
      if isSync then syncLoaded = true else localLoaded = true
      @dispatchEvent "load" if loaded == syncLoaded and localLoaded

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
    @fetchAsync()

  # Asynchronous fetch from synced storage, called only at startup.
  fetchAsync: ->
    chrome.storage.sync.get Object.keys(valuesToLoadHash), @updateSettings.bind(this, true)
    chrome.storage.local.get Object.keys(valuesToLoadHash), @updateSettings.bind(this, false)

  updateSettings: (isSync, items) ->
    # Chrome sets chrome.runtime.lastError if there is an error.
    if chrome.runtime.lastError is undefined
      items_ = {}
      for own key, value of items
        continue unless valuesToLoadHash[key]
        @log "Sync.updateSettings: #{key} <- #{value}"
        @storeAndPropagate key, value, isSync
        items_[key] = JSON.parse value
      Settings.dispatchEvent "update", items_
      loaded isSync
      callback?()
    else
      console.log "callback for Sync.updateSettings() indicates error"
      console.log chrome.runtime.lastError

  # Asynchronous message from chrome.storage.
  handleStorageUpdate: (changes, area) ->
    return if area == "managed"
    items_ = {}
    for own key, change of changes
      continue unless valuesToLoadHash[key]
      value = change.newValue
      @log "handleStorageUpdate: #{key} <- #{value}"
      @storeAndPropagate key, value, (area == "sync")
      items_[key] = JSON.parse value
    Settings.dispatchEvent "update", items_

  # Only ever called from asynchronous chrome.storage callbacks (fetchAsync and handleStorageUpdate).
  storeAndPropagate: (key, value, isSync) ->
    return if not valuesToLoadHash[key]
    return if isSync != @shouldSyncKey key
    return if value and key of values and values[key] is value
    defaultValue = Settings.defaults[key]
    defaultValueJSON = JSON.stringify(defaultValue)

    if value and value != defaultValueJSON
      # Key/value has been changed to non-default value at remote instance.
      @log "storeAndPropagate update: #{key}=#{value}"
      values[key] = value
    else
      # Key has been reset to default value at remote instance.
      @log "storeAndPropagate clear: #{key}"
      if key of values
        delete values[key]

  # Only called synchronously from within vimium, never on a callback.
  # No need to propagate updates to the rest of vimium, that's already been done.
  set: (key, value) ->
    storage = if @shouldSyncKey key then chrome.storage.sync else chrome.storage.local
    @log "set scheduled: #{key}=#{value}"
    key_value = {}
    key_value[key] = value
    storage.set key_value, =>
      # Chrome sets chrome.runtime.lastError if there is an error.
      if chrome.runtime.lastError
        console.log "callback for Sync.set() indicates error: #{key} <- #{value}"
        console.log chrome.runtime.lastError

  # Only called synchronously from within vimium, never on a callback.
  clear: (key) ->
    storage = if @shouldSyncKey key then chrome.storage.sync else chrome.storage.local
    @log "clear scheduled: #{key}"
    storage.remove key, =>
      # Chrome sets chrome.runtime.lastError if there is an error.
      if chrome.runtime.lastError
        console.log "for Sync.clear() indicates error: #{key}"
        console.log chrome.runtime.lastError

  # Should we synchronize this key?
  shouldSyncKey: (key) ->
    key not in @doNotSync

  log: (msg) ->
    console.log "Sync: #{msg}" if @debug


# We use settingsVersion to coordinate any necessary schema changes.
if Utils.compareVersions("1.42", Settings.get("settingsVersion")) != -1
  Settings.set("scrollStepSize", parseFloat Settings.get("scrollStepSize"))
Settings.set("settingsVersion", Utils.getCurrentVersion())

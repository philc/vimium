#
# * Sync.set() and Sync.clear() propagate local changes to chrome.storage.sync.
# * Sync.handleStorageUpdate() listens for changes to chrome.storage.sync and propagates those
#   changes to localStorage and into vimium's internal state.
# * Sync.fetchAsync() polls chrome.storage.sync at startup, similarly propagating
#   changes to localStorage and into vimium's internal state.
#
# Changes are propagated into vimium's state using the same mechanism
# (Settings.performPostUpdateHook) that is used when options are changed on
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
root.Sync = Sync =

  # April 19 2014: Leave logging statements in, but disable debugging. We may need to come back to this, so
  # removing logging now would be premature. However, if users report problems, they are unlikely to notice
  # and make sense of console logs on background pages. So disable it, by default. For genuine errors, we
  # call console.log directly.
  debug: false
  storage: chrome.storage.sync
  doNotSync: ["settingsVersion", "previousVersion"]

  # This is called in main.coffee.
  init: ->
    chrome.storage.onChanged.addListener (changes, area) -> Sync.handleStorageUpdate changes, area
    @fetchAsync()

  # Asynchronous fetch from synced storage, called only at startup.
  fetchAsync: ->
    @storage.get null, (items) =>
      # Chrome sets chrome.runtime.lastError if there is an error.
      if chrome.runtime.lastError is undefined
        for own key, value of items
          @log "fetchAsync: #{key} <- #{value}"
          @storeAndPropagate key, value
      else
        console.log "callback for Sync.fetchAsync() indicates error"
        console.log chrome.runtime.lastError

  # Asynchronous message from synced storage.
  handleStorageUpdate: (changes, area) ->
    for own key, change of changes
      @log "handleStorageUpdate: #{key} <- #{change.newValue}"
      @storeAndPropagate key, change?.newValue

  # Only ever called from asynchronous synced-storage callbacks (fetchAsync and handleStorageUpdate).
  storeAndPropagate: (key, value) ->
    return if not key of Settings.defaults
    return if not @shouldSyncKey key
    return if value and key of localStorage and localStorage[key] is value
    defaultValue = Settings.defaults[key]
    defaultValueJSON = JSON.stringify(defaultValue)

    if value and value != defaultValueJSON
      # Key/value has been changed to non-default value at remote instance.
      @log "storeAndPropagate update: #{key}=#{value}"
      localStorage[key] = value
      Settings.performPostUpdateHook key, JSON.parse(value)
    else
      # Key has been reset to default value at remote instance.
      @log "storeAndPropagate clear: #{key}"
      if key of localStorage
        delete localStorage[key]
      Settings.performPostUpdateHook key, defaultValue

  # Only called synchronously from within vimium, never on a callback.
  # No need to propagate updates to the rest of vimium, that's already been done.
  set: (key, value) ->
    if @shouldSyncKey key
      @log "set scheduled: #{key}=#{value}"
      key_value = {}
      key_value[key] = value
      @storage.set key_value, =>
        # Chrome sets chrome.runtime.lastError if there is an error.
        if chrome.runtime.lastError
          console.log "callback for Sync.set() indicates error: #{key} <- #{value}"
          console.log chrome.runtime.lastError

  # Only called synchronously from within vimium, never on a callback.
  clear: (key) ->
    if @shouldSyncKey key
      @log "clear scheduled: #{key}"
      @storage.remove key, =>
        # Chrome sets chrome.runtime.lastError if there is an error.
        if chrome.runtime.lastError
          console.log "for Sync.clear() indicates error: #{key}"
          console.log chrome.runtime.lastError

  # Should we synchronize this key?
  shouldSyncKey: (key) ->
    key not in @doNotSync

  log: (msg) ->
    console.log "Sync: #{msg}" if @debug

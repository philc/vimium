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
          @storeAndPropagate key, value

  # Asynchronous message from synced storage.
  handleStorageUpdate: (changes, area) ->
    for own key, change of changes
      @storeAndPropagate key, change?.newValue

  # Only ever called from asynchronous synced-storage callbacks (fetchAsync and handleStorageUpdate).
  storeAndPropagate: (key, value) ->
    return unless key of Settings.defaults
    return if not @shouldSyncKey key
    return if value and key of localStorage and localStorage[key] is value
    defaultValue = Settings.defaults[key]
    defaultValueJSON = JSON.stringify(defaultValue)

    if value and value != defaultValueJSON
      # Key/value has been changed to non-default value at remote instance.
      localStorage[key] = value
      Settings.performPostUpdateHook key, JSON.parse(value)
    else
      # Key has been reset to default value at remote instance.
      if key of localStorage
        delete localStorage[key]
      Settings.performPostUpdateHook key, defaultValue

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


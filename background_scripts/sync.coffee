
#
# * Sync.set() and Sync.clear() propagate local changes to chrome.storage.sync.
# * Sync.listener() listens for changes to chrome.storage.sync and propagates those
#   changes to localStorage and into vimium's internal state.
# * Sync.pull() polls chrome.storage.sync at startup, similarly propagating
#   changes to localStorage and into vimium's internal state.
#
# Changes are propagated into vimium's state using the same mechanism
# (Settings.doPostUpdateHook) that is used when options are changed on
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

  debug: true
  storage: chrome.storage.sync
  doNotSync: [ "settingsVersion", "previousVersion" ]

  init: ->
    chrome.storage.onChanged.addListener (changes, area) -> Sync.listener changes, area
    @pull()

  # Asynchronous fetch from synced storage, called only at startup.
  pull: ->
    @storage.get null, (items) ->
      if chrome.runtime.lastError is undefined
        for own key, value of items
          @storeAndPropagate key, value
      else
        @log "chrome sync callback for Sync.pull() indicates error"
        @log chrome.runtime.lastError

  # Asynchronous message from synced storage.
  listener: (changes, area) ->
    for own key, change of changes
      @storeAndPropagate key, change.newValue
  
  # Only ever called from asynchronous synced-storage callbacks (pull and listener).
  storeAndPropagate: (key, value) ->
    # Value must be JSON.stringifed or undefined.
    if not @checkHaveStringOrUndefined value
      return
    # Ignore, we're not accepting this key.
    if not @isSyncKey key
       @log "ignoring: #{key}"
       return
    # Ignore, it's unchanged
    if localStorage[key] is value
       @log "unchanged: #{key}"
       return

    # Ok: accept, store and propagate this update.
    defaultValue = root.Settings.defaults[key]
    defaultValueJSON = JSON.stringify(defaultValue)

    if value && value != defaultValueJSON
      # Key/value has been changed to non-default value at remote instance.
      @log "update: #{key}=#{value}"
      localStorage[key] = value
      root.Settings.doPostUpdateHook key, JSON.parse(value)
    else
      # Key has been reset to default value at remote instance.
      @log "clear: #{key}"
      delete localStorage[key]
      root.Settings.doPostUpdateHook key, defaultValue

  # Only called synchronously from within vimium, never on a callback.
  # No need to propagate updates into the rest of vimium.
  set: (key, value) ->
    # value has already been JSON.stringifed
    if not @checkHaveString value
      return
    #
    if @isSyncKey key
      @storage.set @mkKeyValue(key,value), ->
        if chrome.runtime.lastError
          @log "chrome sync callback for Sync.set() indicates error: " + key
          @log chrome.runtime.lastError
      @log "set scheduled: #{key}=#{value}"

  # Only called synchronously from within vimium, never on a callback.
  clear: (key) ->
    if @isSyncKey key
      @storage.remove key, ->
        if chrome.runtime.lastError
          @log "chrome sync callback for Sync.clear() indicates error: " + key
          @log chrome.runtime.lastError

  # Should we synchronize this key?
  isSyncKey: (key) ->
    key not in @doNotSync

  # There has to be a more elegant way to do this!
  mkKeyValue: (key, value) ->
    obj = {}
    obj[key] = value
    obj

  # Debugging messages.
  # Disable debugginf by setting root.Sync.debug to anything falsy.
  # Enabled for the time being (18/4/14) -- smblott.
  log: (msg) ->
    console.log "Sync: #{msg}" if @debug

  checkHaveString: (thing) ->
    if typeof(thing) != "string" or not thing
      @log "Sync: Yikes! this should be a non-empty string: #{typeof(thing)} #{thing}"
      return false
    return true

  checkHaveStringOrUndefined: (thing) ->
    if ( typeof(thing) != "string" and typeof(thing) != "undefined" ) or ( typeof(thing) == "string" and not thing )
      @log "Sync: Yikes! this should be a non-empty string or undefined: #{typeof(thing)} #{thing}"
      return false
    return true
  
Sync.init()


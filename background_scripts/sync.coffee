
#
# * Sync.set() and Sync.clear() propagate local changes to chrome.storage.
# * Sync.listener() listens for changes to chrome.storage and propagates those
#   changes to localStorage and into vimium's internal state.
# * Sync.pull() polls chrome.storage at startup, similarly propagating changes
#   to localStorage and into vimium's internal state.
#
# Changes are propagated into vimium's state using the same mechanism that is
# used when options are changed on the options page.
#
# The effect is best-effort synchronization of vimium options/settings between
# chrome/vimium instances, whenever:
#   - chrome is logged in to the user's Google account, and
#   - chrome synchronization is enabled.
#
# NOTE:
#   Values handled within this module are ALWAYS already JSON.stringifed, so
#   they're always non-empty strings.
#

console.log ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
root = exports ? window
root.Sync = Sync = 

  # ##################
  # constants

  debug: true
  storage: chrome.storage.sync
  doNotSync: [ "settingsVersion", "previousVersion" ]

  init: ->
    chrome.storage.onChanged.addListener (changes, area) -> Sync.listener changes, area
    @pull()
    @log "Sync.init()"

  # asynchronous fetch from synced storage, called at startup
  pull: ->
    @storage.get null, (items) ->
      Sync.log "pull callback: #{Sync.callbackStatus()}"
      if not chrome.runtime.lastError
        for own key, value of items
          Sync.storeAndPropagate key, value

  # asynchronous message from synced storage
  listener: (changes, area) ->
    @log "listener: #{area}"
    for own key, change of changes
      @storeAndPropagate key, change.newValue
  
  # only ever called from asynchronous synced-storage callbacks (pull and listener)
  storeAndPropagate: (key, value) ->
    # must be JSON.stringifed or undefined
    @checkHaveStringOrUndefined value
    # ignore, if not accepting this key
    if not @syncKey key
       @log "callback ignoring: #{key}"
       return
    # ignore, if unchanged
    if localStorage[key] == value
       @log "callback unchanged: #{key}"
       return

    # ok: accept, store and propagate update
    defaultValue = root.Settings.defaults[key]
    defaultValueJSON = JSON.stringify(defaultValue) # could cache this to avoid repeated recalculation

    if value && value != defaultValueJSON
      # key/value has been changed to non-default value at remote instance
      @log "callback set: #{key}=#{value}"
      localStorage[key] = value
      root.Settings.doPostUpdateHook key, JSON.parse(value)
    else
      # key has been reset to default value at remote instance
      @log "callback clear: #{key}=#{value}"
      delete localStorage[key]
      root.Settings.doPostUpdateHook key, defaultValue

  # only called synchronously from within vimium, never on a callback
  # no need to propagate updates into the rest of vimium (because that will already have been handled externally)
  set: (key, value) ->
    # value must be JSON.stringifed
    @checkHaveString value
    if value
      if @syncKey key
        @storage.set @mkKeyValue(key,value), -> Sync.logCallback "DONE set", key
        @log "set scheduled: #{key}=#{value}"
    else
      # unreachable? (because value is a JSON string)
      @log "UNREACHABLE in Sync.set(): #{key}"
      @clear key

  # only called synchronously from within vimium, never on a callback
  # no need to propagate updates into the rest of  vimium (because that will already have been handled by externally)
  clear: (key) ->
    if @syncKey key
      @storage.remove key, -> Sync.logCallback "DONE clear", key
      @log "clear scheduled: #{key}"

  # ##################
  # utilities 

  syncKey: (key) ->
    key not in @doNotSync

  # there has to be a more elegant way to do this!
  mkKeyValue: (key, value) ->
    obj = {}
    obj[key] = value
    obj

  # debugging messages
  # disable these by setting root.Sync.debug to anything falsy
  log: (msg) ->
    console.log "sync debug: #{msg}" if @debug

  logCallback: (where, key) ->
    @log "#{where} callback: #{key} #{@callbackStatus()}"

  callbackStatus: ->
    if chrome.runtime.lastError then "ERROR: #{chrome.runtime.lastError.message}" else "(OK)"

  checkHaveString: (thing) ->
    if typeof(thing) != "string" or not thing
      @log "sync.coffee: Yikes! this should be a non-empty string: #{typeof(thing)} #{thing}"

  checkHaveStringOrUndefined: (thing) ->
    if ( typeof(thing) != "string" and typeof(thing) != "undefined" ) or ( typeof(thing) == "string" and not thing )
      @log "sync.coffee: Yikes! this should be a non-empty string or undefined: #{typeof(thing)} #{thing}"
  
  # end of Sync object
  # ##################

Sync.init()


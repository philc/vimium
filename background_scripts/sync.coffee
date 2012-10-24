
#
# All operations on vimium settings go through set/get/clear/has operations
# defined in Settings.coffee.  These use localStorage.  Values are JSON
# stringified.
#
# Sync.set() and Sync.clear() propagate changes of vimium's localStorage to
# Google's synchronized storage API.  Sync.listener() listens for changes to
# synchronized storage and propagates those changes back to localStorage.
# Sync.pull() fetches remotely-stored data at startup.
#
# The effect is to synchronize vimium options/settings between chrome/vimium
# instances, whenever:
#   - synchronization is enabled on the vimium settings page,
#   - chrome is logged in to the user's Google account, and
#   - chrome synchronization is enabled.
#
# CAVEAT:
#   localStorage is a synchronous API, whereas synchronized storage is
#   asynchronous.  If settings are changed on a remote chrome/vimium instance,
#   then a race condition exists when vimium is started up.
#

#
# When is Sync called by vimium?
#   - Sync.set   (called by Settings.set)
#   - Sync.clear (called by Settings.clear)
#
# When is vimium called by Sync?
#   - Sync calls Settings.doPostUpdateHook to propagate asynchronous changes
#     into vimium's state; this is similar to how the options page is handled
#   - Sync calls Settings.get to fetch the default value
#   - Sync also updates localStorage.
#

#
# Values here are ALWAYS JSON.stringifed (that's handled by Settings.set)
#

root = exports ? window
root.Sync = Sync = 

  debug: true
  storage: chrome.storage.sync
  ignoreSettings: [ "syncSettings", "settingsVersion" ]

  syncing: ->
    localStorage["syncSettings"]
   
  acceptKey: (key) ->
    @syncing() && key not in @ignoreSettings

  init: ->
    chrome.storage.onChanged.addListener (changes, area) -> Sync.listener changes, area
    @pull() if @syncing()

  # asynchronous fetch from synced storage, called at startup
  pull: ->
    @storage.get null, (items) ->
      Sync.log "pull: #{Sync.callbackStatus()}"
      if not chrome.runtime.lastError
        Sync.log "pull keys: #{Object.keys items}"
        for own key, value of items
          Sync.storeAndPropagate key, value

  # asynchronous message from synced storage
  listener: (changes, area) ->
    @log "listener: #{area}"
    for own key, change of changes
      @storeAndPropagate key, change.newValue
  
  # only ever called from synced-storage callbacks
  storeAndPropagate: (key, value) ->
    @checkHaveStringOrNull(value)
    # ignore, if not accepting this key
    if not @acceptKey key
       @log "callback ignoring: #{key}"
       return
    # ignore, if unchanged
    if localStorage[key] == value
       @log "callback unchanged: #{key}"
       return
    # accept change
    if value
      @log "callback set: #{key}=#{value}"
      localStorage[key] = value
      root.Settings.doPostUpdateHook key, JSON.parse(value)
    else
      @log "callback clear: #{key}=#{value}"
      delete localStorage[key]
      root.Settings.doPostUpdateHook key, root.Settings.get(key) # default value

  # only called from within vimium, never on a callback
  set: (key, value) ->
    @checkHaveString(value)
    if value
      if @acceptKey key
        @storage.set @mkKeyValue(key,value), -> Sync.logCallback "DONE set", key
        @log "set scheduled: #{key}=#{value}"
    else
      @clear key
    # original Settings.set returns value; so return value here too
    value

  # only called from within vimium, never on a callback
  clear: (key) ->
    if @acceptKey key
      @storage.remove key, -> Sync.logCallback "DONE clear", key
      @log "clear scheduled: #{key}"

  # internal use only, there has to be a more elegant way to do this!
  mkKeyValue: (key, value) ->
    obj = {}
    obj[key] = value
    obj

  # debugging stuff; disable by setting root.Sync.debug to anything falsy
  log: (msg) ->
    console.log "sync debug: #{msg}" if @debug

  logCallback: (where, key) ->
    @log "#{where} callback: #{key} #{@callbackStatus()}"

  callbackStatus: ->
    if chrome.runtime.lastError then "ERROR: #{chrome.runtime.lastError.message}" else "(OK)"

  checkHaveString: (str) ->
    if typeof(str) != "string"
      @log "Yikes! this should be a string: #{str}"

  checkHaveStringOrNull: (thing) ->
    if typeof(thing) != "string" && thing != null
      @log "Yikes! this should be a string or null: #{thing}"
  
  # end of Sync
  # ###########

Sync.init()


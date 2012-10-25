
#
# All operations reading or writing settings/options go through
# set/get/clear/has in root.Settings.
#
# Sync.set() and Sync.clear() propagate local changes to synchronized storage.
# Sync.listener() listens for changes to synchronized storage and propagates
# those changes back to localStorage and to vimium's internal state.
# Sync.pull() polls synchronized storage at startup, similarly propagating
# changes.
#
# The overall effect, therefore, is to synchronize vimium options/settings
# between chrome/vimium instances, whenever:
#   - synchronization is enabled via the (new) vimium option.
#   - chrome is logged in to the user's Google account, and
#   - chrome synchronization is enabled.
#
# CAVEAT:
#   localStorage is a synchronous API, whereas synchronized storage is
#   asynchronous.  Because synced storage is asynchronous, race conditions
#   exist.
# 
#   Consider some of the situations which can arise are:
#
#   - two users of the same Google account update their settings at exactly the
#     same time
#
#     This is unlikely to be a common case.  The outcome will be some
#     combination of the options from one user and the updates by the other.
#     It's non-deterministic.
#
#   - A local user has the options page open when another (remote) user saves
#     their options, both users being logged in to the same account.
#
#     When the local user (later) saves their options, they will wholly
#     overwrite the (earlier) remote  user's changes.  This is better than
#     pushing asynchronous changes through to an open options page.
#
#   - At startup, remotely-changed options are propagated asynchronously into
#     the current vimium instance; asynchronously, that is, to the creation of
#     tabs at startup.
#
#     This behaves the same as when options are changed with existing tabs
#     open.  Since most decisions are made by the background page scripts (and
#     updates are propagated to the background page), things should be fine.
#
# These and similar issues are not specific to vimium or this module.  They
# are common to any system (including chrome) for which options and other data
# are synchronized.
#
# BUG:
#   On any browser instance, when sync is first enabled on the options page and
#   "Save Options" is clicked, the settings from the current browser instance
#   are pushed to localStorage and to synced storage -- so any existing option
#   settings in synced storage are overwritten!  This is probably the opposite
#   of what a user might naturally expect (which is that that existing synced
#   option settings are pulled into the current browser instance).
#
#   Possible solution.  Don't have a "Synchronized Settings" option at all.
#   Synchronize if the user is logged in to Google and synchronization is
#   enabled, otherwise don't synchronize.
#
#   Another possible solution.  Have the "Synchronize Settings" option default
#   to "on".  Option settings will then be synchronized before the user has the
#   option to disable synchronization.
#
#   Another possible solution.  Handle the "Synchronize Settings" option
#   specially.  Somehow merge changes from the local instance with those from
#   synced storage.  However, it is not clear what the logic for this would be.
#
#   THIS REQUIRES MORE THOUGHT ...
#

#
# When is Sync called by vimium?
#   - Sync.set   (called by Settings.set)
#   - Sync.clear (called by Settings.clear)
#
# When is vimium called by Sync?
#   - Sync calls Settings.doPostUpdateHook to propagate asynchronous changes
#     into vimium's state; this is similar to how the options page is handled.
#   - Sync peeks into Settings.defaults[key] to fetch the default value for an option.
#   - Sync also updates localStorage.
#

#
# Values handled within this module are ALWAYS already JSON.stringifed.
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
    # must be JSON.stringifed or null or undefined
    @checkHaveStringOrNull(value)
    # ignore, if not accepting this key or not syncing
    if not @acceptKey key
       @log "callback ignoring: #{key}"
       return
    # ignore, if unchanged
    if localStorage[key] == value
       @log "callback unchanged: #{key}"
       return

    # accept, store and propagate update
    defaultValue = root.Settings.defaults[key]
    defaultValueJSON = JSON.stringify(defaultValue) # could cache this to avoid repeated recalculation

    if value && value != defaultValueJSON
      # option value changed at remote instance
      @log "callback set: #{key}=#{value}"
      localStorage[key] = value
      root.Settings.doPostUpdateHook key, JSON.parse(value)
    else
      # option reset to default value at remote instance
      @log "callback clear: #{key}=#{value}"
      delete localStorage[key]
      root.Settings.doPostUpdateHook key, defaultValue

  # only called synchronously from within vimium, never on a callback
  # no need to propagate updates into vimium (because that will already have been handled by vimium)
  set: (key, value) ->
    # value must be JSON.stringifed
    @checkHaveString(value)
    if value
      if @acceptKey key
        @storage.set @mkKeyValue(key,value), -> Sync.logCallback "DONE set", key
        @log "set scheduled: #{key}=#{value}"
    else
      # unreachable? (because value is a JSON string)
      @log "UNREACHABLE in Sync.set(): #{key}"
      @clear key

  # only called synchronously from within vimium, never on a callback
  # no need to propagate updates into vimium (because that will already have been handled by vimium)
  clear: (key) ->
    if @acceptKey key
      @storage.remove key, -> Sync.logCallback "DONE clear", key
      @log "clear scheduled: #{key}"

  # internal use only, there has to be a more elegant way to do this!
  mkKeyValue: (key, value) ->
    obj = {}
    obj[key] = value
    obj

  # debugging stuff; disable debugging by setting root.Sync.debug to anything falsy
  log: (msg) ->
    console.log "sync debug: #{msg}" if @debug

  logCallback: (where, key) ->
    @log "#{where} callback: #{key} #{@callbackStatus()}"

  callbackStatus: ->
    if chrome.runtime.lastError then "ERROR: #{chrome.runtime.lastError.message}" else "(OK)"

  checkHaveString: (thing) ->
    if typeof(thing) != "string"
      @log "Yikes! this should be a string: #{typeof(thing)} #{thing}"

  checkHaveStringOrNull: (thing) ->
    if typeof(thing) != "string" && typeof(thing) != "undefined" && thing != null
      @log "Yikes! this should be a string or undefined or null: #{typeof(thing)} #{thing}"
  
  # end of Sync object
  # ##################

Sync.init()


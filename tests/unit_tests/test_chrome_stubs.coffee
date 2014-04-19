global.chrome ||= {}
global.runtime ||= {}
global.chrome.storage ||= {}

#
# This is a stub for chrome.strorage.sync for testing.
# It does what chrome.storage.sync should do (roughly), but does so synchronously.
#

global.chrome.storage.onChanged ||=
  addListener: (func) -> @func = func

  # Fake a callback from chrome.storage.sync.
  call: (key,value) ->
    chrome.runtime = { lastError: undefined }
    if @func
      @func( @mkKeyValue(key,value), 'synced storage stub' )

  callEmpty: (key) ->
    chrome.runtime = { lastError: undefined }
    if @func
      items = {}
      items[key] = {}
      @func( items, 'synced storage stub' )

  mkKeyValue: (key, value) ->
    obj = {}
    obj[key] = { newValue: value }
    obj

global.chrome.storage.sync ||=
  store: {}

  set: (items,callback) ->
    chrome.runtime = { lastError: undefined }
    for own key, value of items
      @store[key] = value
    if callback
      callback()
    # Now, generate (supposedly asynchronous) notifications for listeners.
    for own key, value of items
      global.chrome.storage.onChanged.call(key,value)

  get: (keys,callback) ->
    chrome.runtime = { lastError: undefined }
    if keys == null
      keys = []
      for own key, value of @store
        keys.push key
    items = {}
    for key in keys
      items[key] = @store[key]
    # Now, generate (supposedly asynchronous) callback
    if callback
      callback items

  remove: (key,callback) ->
    chrome.runtime = { lastError: undefined }
    if key of @store
      delete @store[key]
    if callback
      callback()
    # Now, generate (supposedly asynchronous) notification for listeners.
    global.chrome.storage.onChanged.callEmpty(key)


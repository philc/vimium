
#
# This is a stub for chrome.strorage.sync for testing.
# It does what chrome.storage.sync should do (roughly), but does so synchronously.
# It also provides stubs for a number of other chrome APIs.
#

exports.window = {}
exports.localStorage = {}

global.navigator =
  appVersion: "5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/45.0.2454.85 Safari/537.36"

global.document =
  createElement: -> {}
  addEventListener: ->

global.XMLHttpRequest =
  class XMLHttpRequest
    open: ->
    onload: ->
    send: ->

exports.chrome =
  areRunningVimiumTests: true

  runtime:
    getURL: ->
    getManifest: () ->
      version: "1.2.3"
    onConnect:
      addListener: () -> true
    onMessage:
      addListener: () -> true
    onInstalled:
      addListener: ->

  extension:
    getURL: (path) -> path
    getBackgroundPage: -> {}
    getViews: -> []

  tabs:
    onUpdated:
      addListener: () -> true
    onAttached:
      addListener: () -> true
    onMoved:
      addListener: () -> true
    onRemoved:
      addListener: () -> true
    onActivated:
      addListener: () -> true
    onReplaced:
      addListener: () -> true
    query: () -> true

  webNavigation:
    onHistoryStateUpdated:
      addListener: () ->
    onReferenceFragmentUpdated:
      addListener: () ->

  windows:
    onRemoved:
      addListener: () -> true
    getAll: () -> true
    onFocusChanged:
      addListener: () -> true

  browserAction:
    setBadgeBackgroundColor: ->
  storage:
    # chrome.storage.local
    local:
      get: (_, callback) -> callback?()
      set: (_, callback) -> callback?()
      remove: (_, callback) -> callback?()

    # chrome.storage.onChanged
    onChanged:
      addListener: (func) -> @func = func

      # Fake a callback from chrome.storage.sync.
      call: (key, value) ->
        chrome.runtime.lastError = undefined
        key_value = {}
        key_value[key] = { newValue: value }
        @func(key_value,'sync') if @func

      callEmpty: (key) ->
        chrome.runtime.lastError = undefined
        if @func
          items = {}
          items[key] = {}
          @func(items,'sync')

    session:
      MAX_SESSION_RESULTS: 25

    # chrome.storage.sync
    sync:
      store: {}

      set: (items, callback) ->
        chrome.runtime.lastError = undefined
        for own key, value of items
          @store[key] = value
        callback() if callback
        # Now, generate (supposedly asynchronous) notifications for listeners.
        for own key, value of items
          global.chrome.storage.onChanged.call(key,value)

      get: (keys, callback) ->
        chrome.runtime.lastError = undefined
        if keys == null
          keys = []
          for own key, value of @store
            keys.push key
        items = {}
        for key in keys
          items[key] = @store[key]
        # Now, generate (supposedly asynchronous) callback
        callback items if callback

      remove: (key, callback) ->
        chrome.runtime.lastError = undefined
        if key of @store
          delete @store[key]
        callback() if callback
        # Now, generate (supposedly asynchronous) notification for listeners.
        global.chrome.storage.onChanged.callEmpty(key)

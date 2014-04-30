
#
# This is a stub for chrome.strorage.sync for testing.
# It does what chrome.storage.sync should do (roughly), but does so synchronously.
#

global.chrome =
  runtime: {}

  storage:

    # chrome.storage.onChanged
    onChanged:
      addListener: (func) -> @func = func

      # Fake a callback from chrome.storage.sync.
      call: (key, value) ->
        chrome.runtime = { lastError: undefined }
        key_value = {}
        key_value[key] = { newValue: value }
        @func(key_value,'synced storage stub') if @func

      callEmpty: (key) ->
        chrome.runtime = { lastError: undefined }
        if @func
          items = {}
          items[key] = {}
          @func(items,'synced storage stub')

    # chrome.storage.sync
    sync:
      store: {}

      set: (items, callback) ->
        chrome.runtime = { lastError: undefined }
        for own key, value of items
          @store[key] = value
        callback() if callback
        # Now, generate (supposedly asynchronous) notifications for listeners.
        for own key, value of items
          global.chrome.storage.onChanged.call(key,value)

      get: (keys, callback) ->
        chrome.runtime = { lastError: undefined }
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
        chrome. runtime = { lastError: undefined }
        if key of @store
          delete @store[key]
        callback() if callback
        # Now, generate (supposedly asynchronous) notification for listeners.
        global.chrome.storage.onChanged.callEmpty(key)

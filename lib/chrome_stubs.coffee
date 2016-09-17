#
# Stub the Chrome extension API, if necessary.
#
# NOTE(smblott): This is loaded within the live HUD and Vomnibar windows; however, it has no effect there.
# Within the tests, it provides stubs of various missing Chrome API functions.

window.chrome ?=
  runtime:
    connect: ->
      onMessage:
        addListener: ->
      onDisconnect:
        addListener: ->
      postMessage: ->
    onMessage:
      addListener: ->
    sendMessage: ->
    getManifest: -> version: "1.51"
    getURL: (url) -> "../../#{url}"
  storage:
    local:
      get: ->
      set: ->
    sync:
      get: (_, callback) -> callback? {}
      set: ->
    onChanged:
      addListener: ->
  extension:
    inIncognitoContext: false
    getURL: (url) -> chrome.runtime.getURL url

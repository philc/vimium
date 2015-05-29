#
# Mock the Chrome extension API.
#

root = exports ? window
root.chromeMessages = []

# Add a styleSheet property so that UIComponents and the Tween initialize themselves.
root.styleSheet = {}

document.hasFocus = -> true

root.chrome =
  runtime:
    connect: ->
      onMessage:
        addListener: ->
      onDisconnect:
        addListener: ->
      postMessage: ->
    onMessage:
      addListener: ->
    sendMessage: (message) -> chromeMessages.unshift message
    getManifest: ->
    getURL: (url) -> "../../#{url}"
  storage:
    local:
      get: ->
      set: ->
    sync:
      get: ->
      set: ->
    onChanged:
      addListener: ->
  extension:
    inIncognitoContext: false

#
# Mock the Chrome extension API.
#

root = exports ? window
root.chromeMessages = []

document.hasFocus = -> true

window.forTrusted = (handler) -> handler

fakeManifest =
  version: "1.51"

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
    getManifest: -> fakeManifest
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

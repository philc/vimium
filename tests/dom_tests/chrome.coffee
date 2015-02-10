#
# Mock the Chrome extension API.
#

root = exports ? window
root.chromeMessages = []

document.hasFocus = -> true

root.chrome = {
  runtime: {
    connect: -> {
      onMessage: {
        addListener: ->
      }
      onDisconnect: {
        addListener: ->
      }
      postMessage: ->
      disconnect: ->
    }
    onMessage: {
      addListener: ->
    }
    sendMessage: (message) -> chromeMessages.unshift message
    getManifest: ->
    getURL: (url) -> "../../#{url}"
  }
  storage:
    local:
      get: ->
      set: ->
}

#
# Mock the Chrome extension API.
#

root = exports ? window

root.chrome = {
  extension: {
    connect: -> {
      onMessage: {
        addListener: ->
      }
      postMessage: ->
    }
    onRequest: {
      addListener: ->
    }
    sendRequest: ->
  }
}

#
# Mock the Chrome extension API.
#

root = exports ? window

root.chrome = {
  runtime: {
    connect: -> {
      onMessage: {
        addListener: ->
      }
      postMessage: ->
    }
    onMessage: {
      addListener: ->
    }
    sendMessage: ->
    getManifest: ->
    getURL: (url) ->
      if url == ""
        # We use this to get the origin for our extension. Just pass * so we don't have problems.
        "*"
      else
        "../../" + url
  }
}

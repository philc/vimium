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
  }
}

# Phantomjs does not seem to support MutationObserver;
# see https://github.com/ariya/phantomjs/issues/10715.
class MutationObserver
  constructor: -> true
  observe: -> true

root.MutationObserver = MutationObserver

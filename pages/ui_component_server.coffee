
# Fetch the Vimium secret, register the port received from the parent window, and stop listening for messages
# on the window object. vimiumSecret is accessible only within the current instance of Vimium.  So a
# malicious host page trying to register its own port can do no better than guessing.
window.addEventListener "message", registerPort = (event) ->
  chrome.storage.local.get "vimiumSecret", ({vimiumSecret: secret}) ->
    return unless event.source == window.parent and event.data == secret
    UIComponentServer.portOpen event.ports[0]
    window.removeEventListener "message", registerPort

UIComponentServer =
  ownerPagePort: null
  handleMessage: null

  portOpen: (@ownerPagePort) ->
    @ownerPagePort.onmessage = (event) => @handleMessage? event
    @registerIsReady()

  registerHandler: (@handleMessage) ->

  postMessage: (message) -> @ownerPagePort?.postMessage message
  hide: -> @postMessage "hide"

  # We require both that the DOM is ready and that the port has been opened before the UI component is ready.
  # These events can happen in either order.  We count them, and notify the content script when we've seen
  # both.
  registerIsReady: do ->
    uiComponentIsReadyCount =
      if document.readyState == "loading"
        window.addEventListener "DOMContentLoaded", -> UIComponentServer.registerIsReady()
        0
      else
        1

    ->
      if ++uiComponentIsReadyCount == 2
        @postMessage {name: "setIframeFrameId", iframeFrameId: window.frameId} if window.frameId?
        @postMessage "uiComponentIsReady"

root = exports ? window
root.UIComponentServer = UIComponentServer
root.isVimiumUIComponent = true

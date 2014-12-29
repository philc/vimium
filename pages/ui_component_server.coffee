
# Fetch the Vimium secret, register the port recieved from the parent window, and stop listening for messages
# on the window object. vimiumSecret is accessible only within the current instantion of Vimium.  So a
# malicious host page trying to register its own port can do no better than guessing.
registerPort = (event) ->
  chrome.storage.local.get "vimiumSecret", ({vimiumSecret: secret}) ->
    return unless event.source == window.parent and event.data == secret
    UIComponentServer.portOpen event.ports[0]
    window.removeEventListener "message", registerPort

window.addEventListener "message", registerPort

UIComponentServer =
  ownerPagePort: null
  handleMessage: null

  portOpen: (@ownerPagePort) ->
    @ownerPagePort.onmessage = (event) =>
      @handleMessage event if @handleMessage

  registerHandler: (@handleMessage) ->

  postMessage: (message) ->
    @ownerPagePort.postMessage message if @ownerPagePort

root = exports ? window
root.UIComponentServer = UIComponentServer

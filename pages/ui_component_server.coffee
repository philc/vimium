# Register the port recieved from the parent window, and stop listening for messages on the window object.
window.addEventListener "message", (event) ->
  return unless event.source == window.parent
  currentFunction = arguments.callee

  # Check event.data against iframeMessageSecret so we can determine that this message hasn't been spoofed.
  chrome.storage.local.get "iframeMessageSecret", ({iframeMessageSecret: secret}) ->
    return unless event.data == secret
    UIComponentServer.portOpen event.ports[0]
    window.addEventListener "keydown", (event) -> UIComponentServer.keydownListener event
    window.removeEventListener "message", currentFunction # Stop listening for message events.

UIComponentServer =
  ownerPagePort: null
  messageEventListeners: []
  exitOnEsc: true

  portOpen: (@ownerPagePort) ->
    @ownerPagePort.onmessage = (event) => @handleMessage event

  postMessage: (message) -> @ownerPagePort.postMessage message

  # Execute each event listener on the current event until we get a non-null falsy return value.
  handleMessage: (event) ->
    for listener in @messageEventListeners
      retVal = listener.call this, event
      retVal ?= true
      return false unless retVal
    true

  addEventListener: (type, listener) ->
    if type == "message"
      @messageEventListeners.push listener
    undefined

  removeEventListener: (type, listener) ->
    if type == "message"
      @messageEventListeners = @messageEventListeners.filter (f) -> f != listener
    undefined

  keydownListener: (event) ->
    if @exitOnEsc and KeyboardUtils.isEscape event
      @postMessage "hide"
      false
    else
      true

root = exports ? window
root.UIComponentServer = UIComponentServer

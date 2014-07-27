# Forward the key to the key handler in the background page.
keyPort = chrome.runtime.connect({ name: "keyDown" })

window.addEventListener "message", (event) ->
  return unless event.data?.name == "vimiumKeyDown" # This message isn't intended for us

  return unless event.ports.length == 1
  windowPort = event.ports[0]

  portListeners = [
    # TODO: Do a security test, since anybody can message us
    (event) ->
      windowPort.close() unless event.data == "hi"
      false
    ,(event) ->
      keyPort.postMessage event.data
      true
  ]

  windowPort.onmessage = ->
    # apply the next event listener in the queue
    result = portListeners[0].apply this, arguments

    portListeners.shift() unless result == true

  windowPort.postMessage null

, false

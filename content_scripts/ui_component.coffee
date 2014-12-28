class UIComponent
  iframeElement: null
  iframePort: null
  messageEventListeners: []
  showStyle: ""
  hideStyle: ""

  constructor: (iframeUrl, className) ->
    @iframeElement = document.createElement "iframe"
    @iframeElement.className = className
    @iframeElement.seamless = "seamless"
    @iframeElement.src = chrome.runtime.getURL iframeUrl
    @iframeElement.addEventListener "load", => @openPort()
    document.documentElement.appendChild @iframeElement
    @hide()

  # Open a port and pass it to the iframe via window.postMessage.
  openPort: ->
    messageChannel = new MessageChannel()
    @iframePort = messageChannel.port1
    @iframePort.onmessage = (event) => @handleMessage event

    # Get iframeMessageSecret so the iframe can determine that our message isn't the page impersonating us.
    chrome.storage.local.get "iframeMessageSecret", ({iframeMessageSecret: secret}) =>
      @iframeElement.contentWindow.postMessage secret, chrome.runtime.getURL(""), [messageChannel.port2]

  postMessage: (data) -> @iframePort.postMessage data

  # Execute each event listener on the current event until we get a falsy return value.
  handleMessage: (event) ->
    for listener in @messageEventListeners
      retVal = listener.call this, event
      return false unless retVal
    true

  addEventListener: (type, listener) ->
    if type == "message"
      @messageEventListeners.push listener
    undefined

  removeEventListener: (type, listener) ->
    if type == "message"
      listenerIndex = @messageEventListeners.indexOf listener
      if listenerIndex > -1
        @messageEventListeners = @messageEventListeners.splice listenerIndex, 1
    undefined

  setHideStyle: (@hideStyle) ->
    @hide() if @showing == false

  setShowStyle: (@showStyle) ->
    @show() if @showing == true

  show: ->
    return unless @iframeElement?
    @iframeElement.setAttribute "style", @showStyle
    @iframeElement.focus()
    @showing = true

  hide: ->
    return unless @iframeElement?
    @iframeElement.setAttribute "style", @hideStyle
    @showing = false

root = exports ? window
root.UIComponent = UIComponent

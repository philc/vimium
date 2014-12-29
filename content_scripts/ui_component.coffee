class UIComponent
  iframeElement: null
  iframePort: null
  messageEventListeners: []
  showStyle: "display: block;"
  hideStyle: "display: none;"

  constructor: (iframeUrl, className, showStyle, hideStyle) ->
    @iframeElement = document.createElement "iframe"
    @iframeElement.className = className
    @iframeElement.seamless = "seamless"
    @iframeElement.src = chrome.runtime.getURL iframeUrl
    @iframeElement.addEventListener "load", => @openPort()
    document.documentElement.appendChild @iframeElement

    @setShowStyle showStyle if showStyle?
    @setHideStyle hideStyle if showStyle?
    @hide()

  # Open a port and pass it to the iframe via window.postMessage.
  openPort: ->
    messageChannel = new MessageChannel()
    @iframePort = messageChannel.port1
    @iframePort.onmessage = (event) => @handleMessage event

    # Get iframeMessageSecret so the iframe can determine that our message isn't the page impersonating us.
    chrome.storage.local.get "iframeMessageSecret", ({iframeMessageSecret: secret}) =>
      @iframeElement.contentWindow.postMessage secret, chrome.runtime.getURL(""), [messageChannel.port2]

  postMessage: (message) -> @iframePort.postMessage message

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

  setHideStyle: (@hideStyle) ->
    @hide() if @showing == false

  setShowStyle: (@showStyle) ->
    @show() if @showing == true

  setStyles: (@showStyle = @showStyle, @hideStyle = @hideStyle) ->
    if @showing
      @show()
    else
      @hide()

  show: (message) ->
    @postMessage message if message?
    @iframeElement.setAttribute "style", @showStyle
    @iframeElement.focus()
    @showing = true

  hide: ->
    @iframeElement.setAttribute "style", @hideStyle
    window.focus()
    @showing = false

handleHideMessage = (event) ->
  if event.data == "hide"
    @hide()
    false
  else
    true

root = exports ? window
root.UIComponent = UIComponent

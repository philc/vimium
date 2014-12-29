class UIComponent
  iframeElement: null
  iframePort: null
  showing: true
  showStyle: "display: block;"
  hideStyle: "display: none;"

  constructor: (iframeUrl, className, @handleMessage) ->
    @iframeElement = document.createElement "iframe"
    @iframeElement.className = className
    @iframeElement.seamless = "seamless"
    @iframeElement.src = chrome.runtime.getURL iframeUrl
    @iframeElement.addEventListener "load", => @openPort()
    document.documentElement.appendChild @iframeElement
    # Hide iframe, but don't interfere with the focus.
    @hide false

  # Open a port and pass it to the iframe via window.postMessage.
  openPort: ->
    messageChannel = new MessageChannel()
    @iframePort = messageChannel.port1
    @iframePort.onmessage = (event) => @handleMessage event

    # Get vimiumSecret so the iframe can determine that our message isn't the page impersonating us.
    chrome.storage.local.get "vimiumSecret", ({vimiumSecret: secret}) =>
      @iframeElement.contentWindow.postMessage secret, chrome.runtime.getURL(""), [messageChannel.port2]

  postMessage: (message) ->
    @iframePort.postMessage message

  activate: (message) ->
    @postMessage message if message?
    if @showing
      # NOTE(smblott) Experimental.  Not sure this is a great idea. If the iframe was already showing, then
      # the user gets no visual feedback when it is re-focused.  So flash its border.
      borderWas = @iframeElement.style.border
      @iframeElement.style.border = '5px solid yellow'
      setTimeout((=> @iframeElement.style.border = borderWas), 200)
    else
      @iframeElement.setAttribute "style", @showStyle
      @showing = true
    @iframeElement.focus()

  hide: (focusWindow=true)->
    if @showing
      @iframeElement.setAttribute "style", @hideStyle
      # TODO(smblott) Is window always the right thing to focus, here?
      window.focus() if focusWindow
      @showing = false

root = exports ? window
root.UIComponent = UIComponent

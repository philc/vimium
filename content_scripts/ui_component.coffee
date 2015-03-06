class UIComponent
  iframeElement: null
  iframePort: null
  showing: null

  constructor: (iframeUrl, className, @handleMessage) ->
    @iframeElement = document.createElement "iframe"
    @iframeElement.className = className
    @iframeElement.seamless = "seamless"
    @iframeElement.src = chrome.runtime.getURL iframeUrl
    @iframeElement.addEventListener "load", => @openPort()
    document.documentElement.appendChild @iframeElement
    @showing = true # The iframe is visible now.
    # Hide the iframe, but don't interfere with the focus.
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
    @show() unless @showing
    @iframeElement.focus()

  show: (message) ->
    @postMessage message if message?
    @iframeElement.classList.remove "vimiumUIComponentHidden"
    @iframeElement.classList.add "vimiumUIComponentShowing"
    window.addEventListener "focus", @onFocus = (event) =>
      if event.target == window
        window.removeEventListener "focus", @onFocus
        @onFocus = null
        @postMessage "hide"
    @showing = true

  hide: (focusWindow = true)->
    @iframeElement.classList.remove "vimiumUIComponentShowing"
    @iframeElement.classList.add "vimiumUIComponentHidden"
    window.removeEventListener "focus", @onFocus if @onFocus
    @onFocus = null
    window.focus() if focusWindow
    @showing = false

root = exports ? window
root.UIComponent = UIComponent

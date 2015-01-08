class UIComponent
  iframeElement: null
  iframePort: null
  showing: null
  loaded: false
  queuedActions: []

  constructor: (iframeUrl, className, @handleMessage) ->
    @iframeElement = document.createElement "iframe"
    @iframeElement.className = className
    @iframeElement.seamless = "seamless"
    @iframeElement.src = chrome.runtime.getURL iframeUrl
    @iframeElement.addEventListener "load", => @openPort()
    document.documentElement.appendChild @iframeElement
    @showing = true # The iframe is visible now.
    # Hide the iframe, but don't interfere with the focus.
    @hide false, true

  # Open a port and pass it to the iframe via window.postMessage.
  openPort: ->
    messageChannel = new MessageChannel()
    @iframePort = messageChannel.port1
    @iframePort.onmessage = (event) => @handleMessage event

    # Get vimiumSecret so the iframe can determine that our message isn't the page impersonating us.
    chrome.storage.local.get "vimiumSecret", ({vimiumSecret: secret}) =>
      @iframeElement.contentWindow.postMessage secret, chrome.runtime.getURL(""), [messageChannel.port2]
      @loaded = true
      @onLoad()

  queueAction: (functionName, args) -> @queuedActions.push {functionName, args}

  onLoad: ->
    return unless @loaded
    # Run queued actions.
    for {functionName, args} in @queuedActions
      this[functionName].apply this, args
    @queuedActions = null # No more actions should get queued, so make @queuedActions.push error if we try.

  postMessage: (message) ->
    unless @loaded
      @queueAction "postMessage", arguments
      return

    @iframePort.postMessage message

  activate: (message) ->
    unless @loaded
      @queueAction "activate", arguments
      return

    @postMessage message if message?
    if @showing
      # NOTE(smblott) Experimental.  Not sure this is a great idea. If the iframe was already showing, then
      # the user gets no visual feedback when it is re-focused.  So flash its border.
      @iframeElement.classList.add "vimiumUIComponentReactivated"
      setTimeout((=> @iframeElement.classList.remove "vimiumUIComponentReactivated"), 200)
    else
      @show()
    @iframeElement.focus()

  show: (message) ->
    unless @loaded
      @queueAction "show", arguments
      return

    @postMessage message if message?
    @iframeElement.classList.remove "vimiumUIComponentHidden"
    @iframeElement.classList.add "vimiumUIComponentVisible"
    @showing = true

  hide: (focusWindow = true, forceImmediate = false) ->
    unless @loaded or forceImmediate
      @queueAction "hide", arguments
      return

    @iframeElement.classList.remove "vimiumUIComponentVisible"
    @iframeElement.classList.add "vimiumUIComponentHidden"
    window.focus() if focusWindow
    @showing = false

root = exports ? window
root.UIComponent = UIComponent

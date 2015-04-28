class UIComponent
  iframeElement: null
  iframePort: null
  showing: null
  options: null

  constructor: (iframeUrl, className, @handleMessage) ->
    styleSheet = document.createElement "style"
    styleSheet.type = "text/css"
    # Default to everything hidden while the stylesheet loads.
    styleSheet.innerHTML = "* {display: none !important;}"
    # Load stylesheet.
    xhr = new XMLHttpRequest()
    xhr.onload = (e) -> styleSheet.innerHTML = xhr.responseText
    xhr.open "GET", chrome.runtime.getURL("content_scripts/vimium.css"), true
    xhr.send()

    @iframeElement = document.createElement "iframe"
    extend @iframeElement,
      className: className
      seamless: "seamless"
      src: chrome.runtime.getURL iframeUrl
    @iframeElement.addEventListener "load", => @openPort()
    shadowWrapper = document.createElement "div"
    # PhantomJS doesn't support createShadowRoot, so guard against its non-existance.
    shadowDOM = shadowWrapper.createShadowRoot?() ? shadowWrapper
    shadowDOM.appendChild styleSheet
    shadowDOM.appendChild @iframeElement
    document.documentElement.appendChild shadowWrapper

    @showing = true # The iframe is visible now.
    # Hide the iframe, but don't interfere with the focus.
    @hide false

    # If any other frame in the current tab receives the focus, then we hide the UI component.
    # NOTE(smblott) This is correct for the vomnibar, but might be incorrect (and need to be revisited) for
    # other UI components.
    chrome.runtime.onMessage.addListener (request) =>
      @postMessage "hide" if @showing and request.name == "frameFocused" and request.focusFrameId != frameId
      false # Free up the sendResponse handler.

  # Open a port and pass it to the iframe via window.postMessage.
  openPort: ->
    messageChannel = new MessageChannel()
    @iframePort = messageChannel.port1
    @iframePort.onmessage = (event) => @handleMessage event

    # Get vimiumSecret so the iframe can determine that our message isn't the page impersonating us.
    chrome.storage.local.get "vimiumSecret", ({vimiumSecret: secret}) =>
      @iframeElement.contentWindow.postMessage secret, chrome.runtime.getURL(""), [messageChannel.port2]

  postMessage: (message) ->
    # We use "?" here because the iframe port is initialized asynchronously, and may not yet be ready.
    @iframePort?.postMessage message

  activate: (@options) ->
    @postMessage @options if @options?
    @show() unless @showing
    @iframeElement.focus()

  show: (message) ->
    @postMessage message if message?
    @iframeElement.classList.remove "vimiumUIComponentHidden"
    @iframeElement.classList.add "vimiumUIComponentShowing"
    # The window may not have the focus.  We focus it now, to prevent the "focus" listener below from firing
    # immediately.
    window.focus()
    window.addEventListener "focus", @onFocus = (event) =>
      if event.target == window
        window.removeEventListener "focus", @onFocus
        @onFocus = null
        @postMessage "hide"
    @showing = true

  hide: (focusWindow = true)->
    @refocusSourceFrame @options?.sourceFrameId if focusWindow
    window.removeEventListener "focus", @onFocus if @onFocus
    @onFocus = null
    @iframeElement.classList.remove "vimiumUIComponentShowing"
    @iframeElement.classList.add "vimiumUIComponentHidden"
    @options = null
    @showing = false

  # Refocus the frame from which the UI component was opened.  This may be different from the current frame.
  # After hiding the UI component, Chrome refocuses the containing frame. To avoid a race condition, we need
  # to wait until that frame first receives the focus, before then focusing the frame which should now have
  # the focus.
  refocusSourceFrame: (sourceFrameId) ->
    if @showing and sourceFrameId? and sourceFrameId != frameId
      refocusSourceFrame = ->
        chrome.runtime.sendMessage
          handler: "sendMessageToFrames"
          message:
            name: "focusFrame"
            frameId: sourceFrameId
            highlight: false
            # Note(smblott) Disabled prior to 1.50 (or post 1.49) release.
            # The UX around flashing the frame isn't quite right yet.  We want the frame to flash only if the
            # user exits the Vomnibar with Escape.
            highlightOnlyIfNotTop: false # true

      if windowIsFocused()
        # We already have the focus.
        refocusSourceFrame()
      else
        # We don't yet have the focus (but we'll be getting it soon).
        window.addEventListener "focus", handler = (event) ->
          if event.target == window
            window.removeEventListener "focus", handler
            refocusSourceFrame()

root = exports ? window
root.UIComponent = UIComponent

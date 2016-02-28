class UIComponent
  iframeElement: null
  iframePort: null
  showing: null
  options: null
  shadowDOM: null
  styleSheetGetter: null

  constructor: (iframeUrl, className, @handleMessage) ->
    styleSheet = DomUtils.createElement "style"
    styleSheet.type = "text/css"
    # Default to everything hidden while the stylesheet loads.
    styleSheet.innerHTML = "iframe {display: none;}"

    # Use an XMLHttpRequest, possibly via the background page, to fetch the stylesheet. This allows us to
    # catch and recover from failures that we could not have caught when using CSS @include (eg. #1817).
    UIComponent::styleSheetGetter ?= new AsyncDataFetcher @fetchFileContents "content_scripts/vimium.css"
    @styleSheetGetter.use (styles) -> styleSheet.innerHTML = styles

    @iframeElement = DomUtils.createElement "iframe"
    extend @iframeElement,
      className: className
      seamless: "seamless"
    shadowWrapper = DomUtils.createElement "div"
    # PhantomJS doesn't support createShadowRoot, so guard against its non-existance.
    @shadowDOM = shadowWrapper.createShadowRoot?() ? shadowWrapper
    @shadowDOM.appendChild styleSheet
    @shadowDOM.appendChild @iframeElement

    @showing = true # The iframe is visible now.
    # Hide the iframe, but don't interfere with the focus.
    @hide false

    # Open a port and pass it to the iframe via window.postMessage.  We use an AsyncDataFetcher to handle
    # requests which arrive before the iframe (and its message handlers) have completed initialization.  See
    # #1679.
    @iframePort = new AsyncDataFetcher (setIframePort) =>
      # We set the iframe source and append the new element here (as opposed to above) to avoid a potential
      # race condition vis-a-vis the "load" event (because this callback runs on "nextTick").
      @iframeElement.src = chrome.runtime.getURL iframeUrl
      document.documentElement.appendChild shadowWrapper

      @iframeElement.addEventListener "load", =>
        # Get vimiumSecret so the iframe can determine that our message isn't the page impersonating us.
        chrome.storage.local.get "vimiumSecret", ({ vimiumSecret }) =>
          { port1, port2 } = new MessageChannel
          port1.onmessage = (event) => @handleMessage event
          @iframeElement.contentWindow.postMessage vimiumSecret, chrome.runtime.getURL(""), [ port2 ]
          setIframePort port1

    # If any other frame in the current tab receives the focus, then we hide the UI component.
    # NOTE(smblott) This is correct for the vomnibar, but might be incorrect (and need to be revisited) for
    # other UI components.
    chrome.runtime.onMessage.addListener (request) =>
      @postMessage "hide" if @showing and request.name == "frameFocused" and request.focusFrameId != frameId
      false # Free up the sendResponse handler.

  # Posts a message (if one is provided), then calls continuation (if provided).  The continuation is only
  # ever called *after* the message has been posted.
  postMessage: (message = null, continuation = null) ->
    @iframePort.use (port) =>
      port.postMessage message if message?
      continuation?()

  activate: (@options) ->
    @postMessage @options, =>
      @show() unless @showing
      @iframeElement.focus()

  show: (message) ->
    @postMessage message, =>
      @iframeElement.classList.remove "vimiumUIComponentHidden"
      @iframeElement.classList.add "vimiumUIComponentVisible"
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
    @iframeElement.classList.remove "vimiumUIComponentVisible"
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

      if windowIsFocused()
        # We already have the focus.
        refocusSourceFrame()
      else
        # We don't yet have the focus (but we'll be getting it soon).
        window.addEventListener "focus", handler = (event) ->
          if event.target == window
            window.removeEventListener "focus", handler
            refocusSourceFrame()

  # Fetch a Vimium file/resource (such as "content_scripts/vimium.css").
  # We try making an XMLHttpRequest request.  That can fail (see #1817), in which case we fetch the
  # file/resource via the background page.
  fetchFileContents: (file) -> (callback) ->
    request = new XMLHttpRequest()

    request.onload = ->
      if request.status == 200
        callback request.responseText
      else
        request.onerror()

    request.onerror = ->
      chrome.runtime.sendMessage
        handler: "fetchFileContents"
        fileName: file
      , callback

    request.open "GET", (chrome.runtime.getURL file), true
    request.send()


root = exports ? window
root.UIComponent = UIComponent

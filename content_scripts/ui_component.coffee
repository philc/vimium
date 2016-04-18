class UIComponent
  iframeElement: null
  iframePort: null
  showing: false
  iframeFrameId: null
  options: null
  shadowDOM: null
  styleSheetGetter: null

  toggleIframeElementClasses: (removeClass, addClass) ->
    @iframeElement.classList.remove removeClass
    @iframeElement.classList.add addClass

  constructor: (iframeUrl, className, @handleMessage) ->
    DomUtils.documentReady =>
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
      @toggleIframeElementClasses "vimiumUIComponentVisible", "vimiumUIComponentHidden"

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
            @iframeElement.contentWindow.postMessage vimiumSecret, chrome.runtime.getURL(""), [ port2 ]
            port1.onmessage = (event) =>
              switch event?.data?.name ? event?.data
                when "uiComponentIsReady"
                  # If any other frame receives the focus, then hide the UI component.
                  chrome.runtime.onMessage.addListener ({name, focusFrameId}) =>
                    if name == "frameFocused" and @options?.focus and focusFrameId not in [frameId, @iframeFrameId]
                      @hide false
                    false # We will not be calling sendResponse.
                  # If this frame receives the focus, then hide the UI component.
                  window.addEventListener "focus", (event) =>
                    if event.target == window and @options?.focus and not @options?.allowBlur
                      @hide false
                    true # Continue propagating the event.
                  # Set the iframe's port, thereby rendering the UI component ready.
                  setIframePort port1
                when "setIframeFrameId" then @iframeFrameId = event.data.iframeFrameId
                when "hide" then @hide()
                else @handleMessage event

  # Post a message (if provided), then call continuation (if provided).  We wait for documentReady() to ensure
  # that the @iframePort set (so that we can use @iframePort.use()).
  postMessage: (message = null, continuation = null) ->
    DomUtils.documentReady =>
      @iframePort.use (port) ->
        port.postMessage message if message?
        continuation?()

  activate: (@options = null) ->
    @postMessage @options, =>
      @toggleIframeElementClasses "vimiumUIComponentHidden", "vimiumUIComponentVisible"
      @iframeElement.focus() if @options?.focus
      @showing = true

  hide: (shouldRefocusOriginalFrame = true) ->
    # We post a non-message (null) to ensure that hide() requests cannot overtake activate() requests.
    @postMessage null, =>
      if @showing
        @showing = false
        @toggleIframeElementClasses "vimiumUIComponentVisible", "vimiumUIComponentHidden"
        if @options?.focus
          @iframeElement.blur()
          if shouldRefocusOriginalFrame
            if @options?.sourceFrameId?
              chrome.runtime.sendMessage
                handler: "sendMessageToFrames",
                message: name: "focusFrame", frameId: @options.sourceFrameId, forceFocusThisFrame: true
            else
              window.focus()
        @options = null
        @postMessage "hidden" # Inform the UI component that it is hidden.

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

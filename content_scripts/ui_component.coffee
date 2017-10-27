class UIComponent
  iframeElement: null
  iframePort: null
  showing: false
  iframeFrameId: null
  options: null
  shadowDOM: null

  toggleIframeElementClasses: (removeClass, addClass) ->
    @iframeElement.classList.remove removeClass
    @iframeElement.classList.add addClass

  constructor: (iframeUrl, className, @handleMessage) ->
    DomUtils.documentReady =>
      styleSheet = DomUtils.createElement "style"
      styleSheet.type = "text/css"
      # Default to everything hidden while the stylesheet loads.
      styleSheet.innerHTML = "iframe {display: none;}"

      # Fetch "content_scripts/vimium.css" from chrome.storage.local; the background page caches it there.
      chrome.storage.local.get "vimiumCSSInChromeStorage", (items) ->
        styleSheet.innerHTML = items.vimiumCSSInChromeStorage

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
                    if event.target == window and @options?.focus
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
    @iframePort?.use (port) ->
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

root = exports ? (window.root ?= {})
root.UIComponent = UIComponent
extend window, root unless exports?

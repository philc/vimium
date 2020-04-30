class UIComponent

  constructor: (iframeUrl, className, @handleMessage) ->
    @iframeElement = null
    @iframePort = null
    @showing = false
    @iframeFrameId = null
    # TODO(philc): Make the @options object default to {} and remove the null checks.
    @options = null
    @shadowDOM = null

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
      # Firefox doesn't support createShadowRoot, so guard against its non-existance.
      # https://hacks.mozilla.org/2018/10/firefox-63-tricks-and-treats/ says
      # Firefox 63 has enabled Shadow DOM v1 by default
      if shadowWrapper.attachShadow
        @shadowDOM = shadowWrapper.attachShadow(mode: "open")
      else
        @shadowArrwap = shadowWrapper
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
              eventName = null
              if event
                eventName = (if event.data then event.data.name) || event.data
              switch eventName
                when "uiComponentIsReady"
                  # If any other frame receives the focus, then hide the UI component.
                  chrome.runtime.onMessage.addListener ({name, focusFrameId}) =>
                    if name == "frameFocused" and @options and @options.focus and
                        not [frameId, @iframeFrameId].includes(focusFrameId)
                      @hide false
                    false # We will not be calling sendResponse.
                  # If this frame receives the focus, then hide the UI component.
                  window.addEventListener "focus", (forTrusted (event) =>
                    if event.target == window and @options and @options.focus
                      @hide false
                    true # Continue propagating the event.
                  ), true
                  # Set the iframe's port, thereby rendering the UI component ready.
                  setIframePort port1
                when "setIframeFrameId" then @iframeFrameId = event.data.iframeFrameId
                when "hide" then @hide()
                else @handleMessage event
            return
          return
        return
      if Utils.isFirefox()
          @postMessage name: "settings", isFirefox: true
      return

  toggleIframeElementClasses: (removeClass, addClass) ->
    @iframeElement.classList.remove removeClass
    @iframeElement.classList.add addClass
    return

  # Post a message (if provided), then call continuation (if provided).  We wait for documentReady() to ensure
  # that the @iframePort set (so that we can use @iframePort.use()).
  postMessage: (message = null, continuation = null) ->
    if @iframePort
      @iframePort.use (port) ->
        port.postMessage message if message?
        if continuation
          continuation()
        return
    return

  activate: (@options = null) ->
    @postMessage @options, =>
      @toggleIframeElementClasses "vimiumUIComponentHidden", "vimiumUIComponentVisible"
      if @options && @options.focus
        @iframeElement.focus()
      @showing = true
    return

  hide: (shouldRefocusOriginalFrame = true) ->
    # We post a non-message (null) to ensure that hide() requests cannot overtake activate() requests.
    @postMessage null, =>
      return unless @showing
      @showing = false
      @toggleIframeElementClasses "vimiumUIComponentVisible", "vimiumUIComponentHidden"
      if @options && @options.focus
        @iframeElement.blur()
        if shouldRefocusOriginalFrame
          if @options && @options.sourceFrameId?
            chrome.runtime.sendMessage
              handler: "sendMessageToFrames",
              message: name: "focusFrame", frameId: @options.sourceFrameId, forceFocusThisFrame: true
          else
            Utils.nextTick -> window.focus()
      @options = null
      @postMessage "hidden" # Inform the UI component that it is hidden.
      return
    return

root = exports ? (window.root ?= {})
root.UIComponent = UIComponent
extend window, root unless exports?

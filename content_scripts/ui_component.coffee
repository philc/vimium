class UIComponent
  iframeElement: null
  iframePort: null
  showing: null
  options: null
  shadowDOM: null

  constructor: (iframeUrl, className, @handleMessage) ->
    styleSheet = document.createElement "style"

    unless styleSheet.style
      # If this is an XML document, nothing we do here works:
      # * <style> elements show their contents inline,
      # * <iframe> elements don't load any content,
      # * document.createElement generates elements that have style == null and ignore CSS.
      # If this is the case we don't want to pollute the DOM to no or negative effect.  So we bail
      # immediately, and disable all externally-called methods.
      @postMessage = @activate = @show = @hide = ->
        console.log "This vimium feature is disabled because it is incompatible with this page."
      return

    styleSheet.type = "text/css"
    # Default to everything hidden while the stylesheet loads.
    styleSheet.innerHTML = "@import url(\"#{chrome.runtime.getURL("content_scripts/vimium.css")}\");"

    @iframeElement = document.createElement "iframe"
    extend @iframeElement,
      className: className
      seamless: "seamless"
    shadowWrapper = document.createElement "div"
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

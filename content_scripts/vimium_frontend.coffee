#
# This content script must be run prior to domReady so that we perform some operations very early.
#

root = exports ? (window.root ?= {})
# On Firefox, sometimes the variables assigned to window are lost (bug 1408996), so we reinstall them.
# NOTE(mrmr1993): This bug leads to catastrophic failure (ie. nothing works and errors abound).
DomUtils.documentReady ->
  root.extend window, root unless extend?

isEnabledForUrl = true
isIncognitoMode = chrome.extension.inIncognitoContext
normalMode = null

# We track whther the current window has the focus or not.
windowIsFocused = do ->
  windowHasFocus = null
  DomUtils.documentReady -> windowHasFocus = document.hasFocus()
  window.addEventListener "focus", forTrusted (event) ->
    windowHasFocus = true if event.target == window; true
  window.addEventListener "blur", forTrusted (event) ->
    windowHasFocus = false if event.target == window; true
  -> windowHasFocus

# This is set by Frame.registerFrameId(). A frameId of 0 indicates that this is the top frame in the tab.
frameId = null

# For debugging only. This writes to the Vimium log page, the URL of whichis shown on the console on the
# background page.
bgLog = (args...) ->
  args = (arg.toString() for arg in args)
  Frame.postMessage "log", message: args.join " "

# If an input grabs the focus before the user has interacted with the page, then grab it back (if the
# grabBackFocus option is set).
class GrabBackFocus extends Mode

  constructor: ->
    exitEventHandler = =>
      @alwaysContinueBubbling =>
        @exit()
        chrome.runtime.sendMessage handler: "sendMessageToFrames", message: name: "userIsInteractingWithThePage"

    super
      name: "grab-back-focus"
      keydown: exitEventHandler

    @push
      _name: "grab-back-focus-mousedown"
      mousedown: exitEventHandler

    Settings.use "grabBackFocus", (grabBackFocus) =>
      # It is possible that this mode exits (e.g. due to a key event) before the settings are ready -- in
      # which case we should not install this grab-back-focus watcher.
      if @modeIsActive
        if grabBackFocus
          @push
            _name: "grab-back-focus-focus"
            focus: (event) => @grabBackFocus event.target
          # An input may already be focused. If so, grab back the focus.
          @grabBackFocus document.activeElement if document.activeElement
        else
          @exit()

    # This mode is active in all frames.  A user might have begun interacting with one frame without other
    # frames detecting this.  When one GrabBackFocus mode exits, we broadcast a message to inform all
    # GrabBackFocus modes that they should exit; see #2296.
    chrome.runtime.onMessage.addListener listener = ({name}) =>
      if name == "userIsInteractingWithThePage"
        chrome.runtime.onMessage.removeListener listener
        @exit() if @modeIsActive
      false # We will not be calling sendResponse.

  grabBackFocus: (element) ->
    return @continueBubbling unless DomUtils.isFocusable element
    element.blur()
    @suppressEvent

# Pages can load new content dynamically and change the displayed URL using history.pushState. Since this can
# often be indistinguishable from an actual new page load for the user, we should also re-start GrabBackFocus
# for these as well. This fixes issue #1622.
handlerStack.push
  _name: "GrabBackFocus-pushState-monitor"
  click: (event) ->
    # If a focusable element is focused, the user must have clicked on it. Retain focus and bail.
    return true if DomUtils.isFocusable document.activeElement

    target = event.target
    while target
      # Often, a link which triggers a content load and url change with javascript will also have the new
      # url as it's href attribute.
      if target.tagName == "A" and
         target.origin == document.location.origin and
         # Clicking the link will change the url of this frame.
         (target.pathName != document.location.pathName or
          target.search != document.location.search) and
         (target.target in ["", "_self"] or
          (target.target == "_parent" and window.parent == window) or
          (target.target == "_top" and window.top == window))
        return new GrabBackFocus()
      else
        target = target.parentElement
    true

installModes = ->
  # Install the permanent modes. The permanently-installed insert mode tracks focus/blur events, and
  # activates/deactivates itself accordingly.
  normalMode = new NormalMode
  # Initialize components upon which normal mode depends.
  Scroller.init()
  FindModeHistory.init()
  new InsertMode permanent: true
  new GrabBackFocus if isEnabledForUrl
  normalMode # Return the normalMode object (for the tests).

#
# Complete initialization work that should be done prior to DOMReady.
#
initializePreDomReady = ->
  installListeners()
  Frame.init()
  checkIfEnabledForUrl document.hasFocus()

  requestHandlers =
    focusFrame: (request) -> if (frameId == request.frameId) then focusThisFrame request
    getScrollPosition: (ignoredA, ignoredB, sendResponse) ->
      sendResponse scrollX: window.scrollX, scrollY: window.scrollY if frameId == 0
    setScrollPosition: setScrollPosition
    frameFocused: -> # A frame has received the focus; we don't care here (UI components handle this).
    checkEnabledAfterURLChange: checkEnabledAfterURLChange
    runInTopFrame: ({sourceFrameId, registryEntry}) ->
      NormalModeCommands[registryEntry.command] sourceFrameId, registryEntry if DomUtils.isTopFrame()
    linkHintsMessage: (request) -> HintCoordinator[request.messageType] request

  chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
    request.isTrusted = true
    # Some requests intended for the background page are delivered to the options page too; ignore them.
    unless request.handler and not request.name
      # Some request are handled elsewhere; ignore them too.
      unless request.name in ["userIsInteractingWithThePage"]
        if isEnabledForUrl or request.name in ["checkEnabledAfterURLChange", "runInTopFrame"]
          requestHandlers[request.name] request, sender, sendResponse
    false # Ensure that the sendResponse callback is freed.

# Wrapper to install event listeners.  Syntactic sugar.
installListener = (element, event, callback) ->
  element.addEventListener(event, forTrusted(->
    root.extend window, root unless extend? # See #2800.
    if isEnabledForUrl then callback.apply(this, arguments) else true
  ), true)

#
# Installing or uninstalling listeners is error prone. Instead we elect to check isEnabledForUrl each time so
# we know whether the listener should run or not.
# Run this as early as possible, so the page can't register any event handlers before us.
# Note: We install the listeners even if Vimium is disabled.  See comment in commit
# 6446cf04c7b44c3d419dc450a73b60bcaf5cdf02.
#
installListeners = Utils.makeIdempotent ->
  # Key event handlers fire on window before they do on document. Prefer window for key events so the page
  # can't set handlers to grab the keys before us.
  for type in ["keydown", "keypress", "keyup", "click", "focus", "blur", "mousedown", "scroll"]
    do (type) -> installListener window, type, (event) -> handlerStack.bubbleEvent type, event
  installListener document, "DOMActivate", (event) -> handlerStack.bubbleEvent 'DOMActivate', event

#
# Whenever we get the focus:
# - Tell the background page this frame's URL.
# - Check if we should be enabled.
#
onFocus = forTrusted (event) ->
  if event.target == window
    chrome.runtime.sendMessage handler: "frameFocused"
    checkIfEnabledForUrl true

# We install these listeners directly (that is, we don't use installListener) because we still need to receive
# events when Vimium is not enabled.
window.addEventListener "focus", onFocus
window.addEventListener "hashchange", -> checkEnabledAfterURLChange()

initializeOnDomReady = ->
  # Tell the background page we're in the domReady state.
  Frame.postMessage "domReady"

Frame =
  port: null
  listeners: {}

  addEventListener: (handler, callback) -> @listeners[handler] = callback
  postMessage: (handler, request = {}) -> @port.postMessage extend request, {handler}
  linkHintsMessage: (request) -> HintCoordinator[request.messageType] request
  registerFrameId: ({chromeFrameId}) ->
    frameId = root.frameId = window.frameId = chromeFrameId
    # We register a frame immediately only if it is focused or its window isn't tiny.  We register tiny
    # frames later, when necessary.  This affects focusFrame() and link hints.
    if windowIsFocused() or not DomUtils.windowIsTooSmall()
      Frame.postMessage "registerFrame"
    else
      postRegisterFrame = ->
        window.removeEventListener "focus", focusHandler
        window.removeEventListener "resize", resizeHandler
        Frame.postMessage "registerFrame"
      window.addEventListener "focus", focusHandler = forTrusted (event) ->
        postRegisterFrame() if event.target == window
      window.addEventListener "resize", resizeHandler = forTrusted (event) ->
        postRegisterFrame() unless DomUtils.windowIsTooSmall()

  init: ->
    @port = chrome.runtime.connect name: "frames"

    @port.onMessage.addListener (request) =>
      root.extend window, root unless extend? # See #2800 and #2831.
      (@listeners[request.handler] ? this[request.handler]) request

    # We disable the content scripts when we lose contact with the background page, or on unload.
    @port.onDisconnect.addListener disconnect = Utils.makeIdempotent => @disconnect()
    window.addEventListener "unload", forTrusted disconnect

  disconnect: ->
    try @postMessage "unregisterFrame"
    try @port.disconnect()
    @postMessage = @disconnect = ->
    @port = null
    @listeners = {}
    HintCoordinator.exit isSuccess: false
    handlerStack.reset()
    isEnabledForUrl = false
    window.removeEventListener "focus", onFocus
    window.removeEventListener "hashchange", checkEnabledAfterURLChange

setScrollPosition = ({ scrollX, scrollY }) ->
  DomUtils.documentReady ->
    if DomUtils.isTopFrame()
      window.focus()
      document.body.focus()
      if 0 < scrollX or 0 < scrollY
        Marks.setPreviousPosition()
        window.scrollTo scrollX, scrollY

flashFrame = do ->
  highlightedFrameElement = null

  ->
    highlightedFrameElement ?= do ->
      # Create a shadow DOM wrapping the frame so the page's styles don't interfere with ours.
      highlightedFrameElement = DomUtils.createElement "div"
      # PhantomJS doesn't support createShadowRoot, so guard against its non-existance.
      _shadowDOM = highlightedFrameElement.createShadowRoot?() ? highlightedFrameElement

      # Inject stylesheet.
      _styleSheet = DomUtils.createElement "style"
      _styleSheet.innerHTML = "@import url(\"#{chrome.runtime.getURL("content_scripts/vimium.css")}\");"
      _shadowDOM.appendChild _styleSheet

      _frameEl = DomUtils.createElement "div"
      _frameEl.className = "vimiumReset vimiumHighlightedFrame"
      _shadowDOM.appendChild _frameEl

      highlightedFrameElement

    document.documentElement.appendChild highlightedFrameElement
    Utils.setTimeout 200, -> highlightedFrameElement.remove()

#
# Called from the backend in order to change frame focus.
#
focusThisFrame = (request) ->
  unless request.forceFocusThisFrame
    if DomUtils.windowIsTooSmall() or document.body?.tagName.toLowerCase() == "frameset"
      # This frame is too small to focus or it's a frameset. Cancel and tell the background page to focus the
      # next frame instead.  This affects sites like Google Inbox, which have many tiny iframes. See #1317.
      chrome.runtime.sendMessage handler: "nextFrame"
      return
  window.focus()
  # On Firefox, window.focus doesn't always draw focus back from a child frame (bug 554039).
  # We blur the active element if it is an iframe, which gives the window back focus as intended.
  document.activeElement.blur() if document.activeElement.tagName.toLowerCase() == "iframe"
  flashFrame() if request.highlight

# Used by focusInput command.
root.lastFocusedInput = do ->
  # Track the most recently focused input element.
  recentlyFocusedElement = null
  window.addEventListener "focus",
    forTrusted (event) ->
      DomUtils = window.DomUtils ? root.DomUtils # Workaround FF bug 1408996.
      if DomUtils.isEditable event.target
        recentlyFocusedElement = event.target
  , true
  -> recentlyFocusedElement

# Checks if Vimium should be enabled or not in this frame.  As a side effect, it also informs the background
# page whether this frame has the focus, allowing the background page to track the active frame's URL and set
# the page icon.
checkIfEnabledForUrl = do ->
  Frame.addEventListener "isEnabledForUrl", (response) ->
    {isEnabledForUrl, passKeys, frameIsFocused, isFirefox} = response
    Utils.isFirefox = -> isFirefox
    installModes() unless normalMode
    normalMode.setPassKeys passKeys
    # Hide the HUD if we're not enabled.
    HUD.hide true, false unless isEnabledForUrl

  (frameIsFocused = windowIsFocused()) ->
    Frame.postMessage "isEnabledForUrl", {frameIsFocused, url: window.location.toString()}

# When we're informed by the background page that a URL in this tab has changed, we check if we have the
# correct enabled state (but only if this frame has the focus).
checkEnabledAfterURLChange = forTrusted ->
  checkIfEnabledForUrl() if windowIsFocused()

# If we are in the help dialog iframe, then HelpDialog is already defined with the necessary functions.
root.HelpDialog ?=
  helpUI: null
  isShowing: -> @helpUI?.showing
  abort: -> @helpUI.hide false if @isShowing()

  toggle: (request) ->
    DomUtils.documentComplete =>
      @helpUI ?= new UIComponent "pages/help_dialog.html", "vimiumHelpDialogFrame", ->
    if @helpUI? and @isShowing()
      @helpUI.hide()
    else if @helpUI?
      @helpUI.activate extend request,
        name: "activate", focus: true

initializePreDomReady()
DomUtils.documentReady initializeOnDomReady

root.handlerStack = handlerStack
root.frameId = frameId
root.Frame = Frame
root.windowIsFocused = windowIsFocused
root.bgLog = bgLog
# These are exported for normal mode and link-hints mode.
extend root, {focusThisFrame}
# These are exported only for the tests.
extend root, {installModes}
extend window, root unless exports?

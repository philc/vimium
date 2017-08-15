#
# A heads-up-display (HUD) for showing Vimium page operations.
# Note: you cannot interact with the HUD until document.body is available.
#
HUD =
  tween: null
  hudUI: null
  _displayElement: null
  findMode: null
  abandon: -> @hudUI?.hide false

  pasteListener: null # Set by @pasteFromClipboard to handle the value returned by pasteResponse

  # This HUD is styled to precisely mimick the chrome HUD on Mac. Use the "has_popup_and_link_hud.html"
  # test harness to tweak these styles to match Chrome's. One limitation of our HUD display is that
  # it doesn't sit on top of horizontal scrollbars like Chrome's HUD does.

  init: ->
    @hudUI ?= new UIComponent "pages/hud.html", "vimiumHUDFrame", ({data}) => this[data.name]? data
    @tween ?= new Tween "iframe.vimiumHUDFrame.vimiumUIComponentVisible", @hudUI.shadowDOM

  showForDuration: (text, duration) ->
    @show(text)
    @_showForDurationTimerId = setTimeout((=> @hide()), duration)

  show: (text) ->
    DomUtils.documentComplete =>
      @init()
      clearTimeout(@_showForDurationTimerId)
      @hudUI.activate {name: "show", text}
      @tween.fade 1.0, 150

  showFindMode: (@findMode = null) ->
    DomUtils.documentComplete =>
      @init()
      @hudUI.activate name: "showFindMode"
      @tween.fade 1.0, 150

  search: (data) ->
    # NOTE(mrmr1993): On Firefox, window.find moves the window focus away from the HUD. We use postFindFocus
    # to put it back, so the user can continue typing.
    @findMode.findInPlace data.query, {"postFindFocus": @hudUI.iframeElement.contentWindow}

    # Show the number of matches in the HUD UI.
    matchCount = if FindMode.query.parsedQuery.length > 0 then FindMode.query.matchCount else 0
    showMatchText = FindMode.query.rawQuery.length > 0
    @hudUI.postMessage {name: "updateMatchesCount", matchCount, showMatchText}

  # Hide the HUD.
  # If :immediate is falsy, then the HUD is faded out smoothly (otherwise it is hidden immediately).
  # If :updateIndicator is truthy, then we also refresh the mode indicator.  The only time we don't update the
  # mode indicator, is when hide() is called for the mode indicator itself.
  hide: (immediate = false, updateIndicator = true) ->
    if @hudUI? and @tween?
      clearTimeout @_showForDurationTimerId
      @tween.stop()
      if immediate
        if updateIndicator then Mode.setIndicator() else @hudUI.hide()
      else
        @tween.fade 0, 150, => @hide true, updateIndicator

  # These parameters describe the reason find mode is exiting, and come from the HUD UI component.
  hideFindMode: ({exitEventIsEnter, exitEventIsEscape}) ->
    @findMode.checkReturnToViewPort()

    # An element won't receive a focus event if the search landed on it while we were in the HUD iframe. To
    # end up with the correct modes active, we create a focus/blur event manually after refocusing this
    # window.
    window.focus()

    focusNode = DomUtils.getSelectionFocusElement()
    document.activeElement?.blur()
    focusNode?.focus?()

    if exitEventIsEnter
      FindMode.handleEnter()
      if FindMode.query.hasResults
        postExit = -> new PostFindMode
    else if exitEventIsEscape
      # We don't want FindMode to handle the click events that FindMode.handleEscape can generate, so we
      # wait until the mode is closed before running it.
      postExit = FindMode.handleEscape

    @findMode.exit()
    postExit?()

  # These commands manage copying and pasting from the clipboard in the HUD frame.
  # NOTE(mrmr1993): We need this to copy and paste on Firefox:
  # * an element can't be focused in the background page, so copying/pasting doesn't work
  # * we don't want to disrupt the focus in the page, in case the page is listening for focus/blur events.
  # * the HUD shouldn't be active for this frame while any of the copy/paste commands are running.
  copyToClipboard: (text) ->
    DomUtils.documentComplete =>
      @init()
      @hudUI?.postMessage {name: "copyToClipboard", data: text}

  pasteFromClipboard: (@pasteListener) ->
    DomUtils.documentComplete =>
      @init()
      # Show the HUD frame, so Firefox will actually perform the paste.
      @hudUI.toggleIframeElementClasses "vimiumUIComponentHidden", "vimiumUIComponentVisible"
      @tween.fade 0, 0
      @hudUI.postMessage {name: "pasteFromClipboard"}

  pasteResponse: ({data}) ->
    # Hide the HUD frame again.
    @hudUI.toggleIframeElementClasses "vimiumUIComponentVisible", "vimiumUIComponentHidden"
    @unfocusIfFocused()
    @pasteListener data

  unfocusIfFocused: ->
    document.activeElement.blur() if document.activeElement == @hudUI?.iframeElement

class Tween
  opacity: 0
  intervalId: -1
  styleElement: null

  constructor: (@cssSelector, insertionPoint = document.documentElement) ->
    @styleElement = DomUtils.createElement "style"

    unless @styleElement.style
      # We're in an XML document, so we shouldn't inject any elements. See the comment in UIComponent.
      Tween::fade = Tween::stop = Tween::updateStyle = ->
      return

    @styleElement.type = "text/css"
    @styleElement.innerHTML = ""
    insertionPoint.appendChild @styleElement

  fade: (toAlpha, duration, onComplete) ->
    clearInterval @intervalId
    startTime = (new Date()).getTime()
    fromAlpha = @opacity
    alphaStep = toAlpha - fromAlpha

    performStep = =>
      elapsed = (new Date()).getTime() - startTime
      if (elapsed >= duration)
        clearInterval @intervalId
        @updateStyle toAlpha
        onComplete?()
      else
        value = (elapsed / duration) * alphaStep + fromAlpha
        @updateStyle value

    @updateStyle @opacity
    @intervalId = setInterval performStep, 50

  stop: -> clearInterval @intervalId

  updateStyle: (@opacity) ->
    @styleElement.innerHTML = """
      #{@cssSelector} {
        opacity: #{@opacity};
      }
    """

root = exports ? (window.root ?= {})
root.HUD = HUD
extend window, root unless exports?

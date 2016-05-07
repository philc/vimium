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
    @findMode.findInPlace data.query

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
    focusNode?.focus()

    if exitEventIsEnter
      handleEnterForFindMode()
      if FindMode.query.hasResults
        postExit = -> new PostFindMode
    else if exitEventIsEscape
      # We don't want FindMode to handle the click events that handleEscapeForFindMode can generate, so we
      # wait until the mode is closed before running it.
      postExit = handleEscapeForFindMode

    @findMode.exit()
    postExit?()

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

root = exports ? window
root.HUD = HUD

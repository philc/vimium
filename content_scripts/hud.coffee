#
# A heads-up-display (HUD) for showing Vimium page operations.
# Note: you cannot interact with the HUD until document.body is available.
#
HUD =
  tween: null
  hudUI: null
  _displayElement: null
  findMode: null

  # This HUD is styled to precisely mimick the chrome HUD on Mac. Use the "has_popup_and_link_hud.html"
  # test harness to tweak these styles to match Chrome's. One limitation of our HUD display is that
  # it doesn't sit on top of horizontal scrollbars like Chrome's HUD does.

  init: ->
    unless @hudUI?
      @hudUI = new UIComponent "pages/hud.html", "vimiumHUDFrame", ({data}) =>
        this[data.name]? data
      @tween = new Tween "iframe.vimiumHUDFrame.vimiumUIComponentVisible", @hudUI.shadowDOM

  showForDuration: (text, duration) ->
    @show(text)
    @_showForDurationTimerId = setTimeout((=> @hide()), duration)

  show: (text) ->
    return unless @enabled()
    clearTimeout(@_showForDurationTimerId)
    @hudUI.show {name: "show", text}
    @tween.fade 1.0, 150

  showFindMode: (@findMode = null) ->
    return unless @enabled()
    @hudUI.show {name: "showFindMode", text: ""}
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
    return unless @tween? and @isReady()
    clearTimeout(@_showForDurationTimerId)
    @tween.stop()
    if immediate
      unless updateIndicator
        @hudUI.hide()
        @hudUI.postMessage {name: "hide"}
      Mode.setIndicator() if updateIndicator
    else
      @tween.fade 0, 150, => @hide true, updateIndicator

  hideFindMode: (data) ->
    @findMode.checkReturnToViewPort()

    # An element element won't receive a focus event if the search landed on it while we were in the HUD
    # iframe. To end up with the correct modes active, we create a focus/blur event manually after refocusing
    # this window.
    window.focus()

    focusNode = DomUtils.getSelectionFocusElement()
    document.activeElement?.blur()
    focusNode?.focus()

    {event} = data

    if event.keyCode == keyCodes.enter
      handleEnterForFindMode()
      if FindMode.query.hasResults
        postExit = -> new PostFindMode
    else if KeyboardUtils.isEscape event
      # We don't want FindMode to handle the click events that handleEscapeForFindMode can generate, so we
      # wait until the mode is closed before running it.
      postExit = handleEscapeForFindMode

    @findMode.exit()
    postExit?()

  isReady: do ->
    ready = false
    DomUtils.documentReady -> ready = true
    -> ready and document.body != null and @hudUI?

  enabled: -> true

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

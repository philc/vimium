#
# A heads-up-display (HUD) for showing Vimium page operations.
# Note: you cannot interact with the HUD until document.body is available.
#
HUD =
  tween: null
  hudUI: null
  _displayElement: null

  # This HUD is styled to precisely mimick the chrome HUD on Mac. Use the "has_popup_and_link_hud.html"
  # test harness to tweak these styles to match Chrome's. One limitation of our HUD display is that
  # it doesn't sit on top of horizontal scrollbars like Chrome's HUD does.

  init: ->
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

  showFindMode: (text = "") ->
    return unless @enabled()
    # NOTE(mrmr1993): We set findModeQuery.rawQuery here rather in search while we still handle keys in the
    # main frame. When key handling is moved to the HUD iframe, this line should be deleted, and the
    # equivalent in search should be uncommented.
    findModeQuery.rawQuery = text
    @hudUI.show {name: "showFindMode", text}
    @tween.fade 1.0, 150

  updateMatchesCount: (matchCount, showMatchText = true) ->
    @hudUI.postMessage {name: "updateMatchesCount", matchCount, showMatchText}

  search: (data) ->
    # NOTE(mrmr1993): The following line is disabled as it is currently vulnerable to a race condition when a
    # user types quickly. When all of the key handling is done in the HUD iframe, this should be uncommented,
    # and the equivalent line in showFindMode should be deleted.
    #findModeQuery.rawQuery = data.query
    updateFindModeQuery()
    performFindInPlace()
    showFindModeHUDForQuery()

  # Hide the HUD.
  # If :immediate is falsy, then the HUD is faded out smoothly (otherwise it is hidden immediately).
  # If :updateIndicator is truthy, then we also refresh the mode indicator.  The only time we don't update the
  # mode indicator, is when hide() is called for the mode indicator itself.
  hide: (immediate = false, updateIndicator = true) ->
    return unless @tween?
    clearTimeout(@_showForDurationTimerId)
    @tween.stop()
    if immediate
      unless updateIndicator
        @hudUI.hide()
        @hudUI.postMessage {name: "hide"}
      Mode.setIndicator() if updateIndicator
    else
      @tween.fade 0, 150, => @hide true, updateIndicator

  isReady: do ->
    ready = false
    DomUtils.documentReady -> ready = true
    -> ready and document.body != null

  # A preference which can be toggled in the Options page. */
  enabled: -> !Settings.get("hideHud")

class Tween
  opacity: 0
  intervalId: -1
  styleElement: null

  constructor: (@cssSelector, insertionPoint = document.documentElement) ->
    @styleElement = document.createElement "style"

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

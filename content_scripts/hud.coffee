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
  enabled: -> !settings.get("hideHud")

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

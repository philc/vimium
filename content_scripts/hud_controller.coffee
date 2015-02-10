root = exports ? window

#
# A heads-up-display (HUD) for showing Vimium page operations.
# Note: you cannot interact with the HUD until document.body is available.
#
root.HUD =
  showForDurationTimerId: -1
  hudTween: null
  upgradeTween: null
  hudUI: null
  upgradeUI: null

  # This HUD is styled to precisely mimick the chrome HUD on Mac. Use the "has_popup_and_link_hud.html"
  # test harness to tweak these styles to match Chrome's. One limitation of our HUD display is that
  # it doesn't sit on top of horizontal scrollbars like Chrome's HUD does.

  init: ->
    @hudUI = new UIComponent "pages/HUD.html", "vimiumHUDFrame", ({data}) =>
      this[data.name]? data
    @upgradeUI = new UIComponent "pages/HUD.html", "vimiumUpgradeFrame", ({data}) =>
      this[data.name]? data

    @hudTween = new Tween ".vimiumHUDFrame.vimiumUIComponentVisible"
    @upgradeTween = new Tween ".vimiumUpgradeFrame.vimiumUIComponentVisible"

  showForDuration: (text, duration) ->
    @show text
    @showForDurationTimerId = setTimeout((=> @hide()), duration)

  show: (text) ->
    return unless @enabled()
    clearTimeout @showForDurationTimerId
    @hudUI.show {name: "show", text}
    @hudTween.fade 1.0, 150

  hide: (immediate) ->
    clearTimeout @showForDurationTimerId
    if (immediate)
      @hudUI.hide()
    else
      @hudTween.fade 0, 150, => @hudUI.hide false

  showUpgradeNotification: (version) ->
    @upgradeUI.show {name: "upgrade", version}
    @upgradeTween.fade 1.0, 150

  hideUpgradeNotification: ->
    @upgradeTween.fade 0, 150, => @upgradeUI.hide false

  showFindMode: ->
    clearTimeout @showForDurationTimerId
    @hudUI.activate {name: "find"}
    @hudTween.fade 1.0, 150
    # Refocus the HUD if the user focuses this window.
    window.addEventListener "focus", @focusFindModeHUD, false
    document.documentElement.addEventListener "mouseup", @focusFindModeHUD, false

  focusFindModeHUD: ->
    HUD.hudUI.activate()

  search: (data) ->
    findModeQuery.rawQuery = data.query
    updateFindModeQuery()
    performFindInPlace()
    updateFindModeHUDCount()

  updateMatchesCount: (count) ->
    @hudUI.postMessage {name: "updateMatchesCount", count}

  hideFindMode: (data) ->
    handlers =
      esc: handleEscapeForFindMode
      del: handleDeleteForFindMode
      enter: handleEnterForFindMode
    findModeQuery.rawQuery = data.query
    handlers[data.type]()
    @hudUI.hide()

  isReady: -> document.body != null

  # A preference which can be toggled in the Options page. */
  enabled: -> !settings.get("hideHud")

class Tween
  opacity: 0
  intervalId: -1
  styleElement: null

  constructor: (@cssSelector) ->
    @styleElement = document.createElement "style"
    @styleElement.type = "text/css"
    @styleElement.innerHTML = ""
    document.documentElement.appendChild @styleElement

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

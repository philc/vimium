root = window.Marks = {}

root.activateCreateMode = ->
  handlerStack.push keydown: (e) ->
    keyChar = KeyboardUtils.getKeyChar(event)
    return unless keyChar isnt ""

    if /[A-Z]/.test keyChar
      chrome.runtime.sendMessage {
        handler: 'createMark',
        markName: keyChar
        scrollX: window.scrollX,
        scrollY: window.scrollY
      }, -> HUD.showForDuration chrome.i18n.getMessage("created_global_mark", ["#{keyChar}"]), 1000
    else if /[a-z]/.test keyChar
      [baseLocation, sep, hash] = window.location.href.split '#'
      localStorage["vimiumMark|#{baseLocation}|#{keyChar}"] = JSON.stringify
        scrollX: window.scrollX,
        scrollY: window.scrollY
      HUD.showForDuration chrome.i18n.getMessage("created_local_mark", ["#{keyChar}"]), 1000

    @remove()

    false

root.activateGotoMode = ->
  handlerStack.push keydown: (e) ->
    keyChar = KeyboardUtils.getKeyChar(event)
    return unless keyChar isnt ""

    if /[A-Z]/.test keyChar
      chrome.runtime.sendMessage
        handler: 'gotoMark'
        markName: keyChar
    else if /[a-z]/.test keyChar
      [baseLocation, sep, hash] = window.location.href.split '#'
      markString = localStorage["vimiumMark|#{baseLocation}|#{keyChar}"]
      if markString?
        mark = JSON.parse markString
        window.scrollTo mark.scrollX, mark.scrollY
        HUD.showForDuration chrome.i18n.getMessage("jumped_to_local_mark", ["#{keyChar}"]), 1000

    @remove()

    false

root = window.Marks = {}

root.activateCreateMode = ->
  handlerStack.push keydown: (e) ->
    keyChar = KeyboardUtils.getKeyChar(event)
    return unless keyChar isnt ""

    if /[A-Z]/.test keyChar
      chrome.extension.sendRequest {
        handler: 'createMark',
        markName: keyChar
        scrollX: window.scrollX,
        scrollY: window.scrollY
      }, -> HUD.showForDuration "已创建全局标记'#{keyChar}'", 1000
    else if /[a-z]/.test keyChar
      [baseLocation, sep, hash] = window.location.href.split '#'
      localStorage["vimiumMark|#{baseLocation}|#{keyChar}"] = JSON.stringify
        scrollX: window.scrollX,
        scrollY: window.scrollY
      HUD.showForDuration "已在当前页创建标记'#{keyChar}'", 1000

    @remove()

    false

root.activateGotoMode = ->
  handlerStack.push keydown: (e) ->
    keyChar = KeyboardUtils.getKeyChar(event)
    return unless keyChar isnt ""

    if /[A-Z]/.test keyChar
      chrome.extension.sendRequest
        handler: 'gotoMark'
        markName: keyChar
    else if /[a-z]/.test keyChar
      [baseLocation, sep, hash] = window.location.href.split '#'
      markString = localStorage["vimiumMark|#{baseLocation}|#{keyChar}"]
      if markString?
        mark = JSON.parse markString
        window.scrollTo mark.scrollX, mark.scrollY
        HUD.showForDuration "跳转到当面页的'#{keyChar}'标记处", 1000

    @remove()

    false

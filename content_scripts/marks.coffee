
exit = (mode, continuation = null) ->
  mode.exit()
  continuation?()

Marks =
  activateCreateMode: ->
    mode = new Mode
      name: "create-mark"
      indicator: "Create mark?"
      suppressAllKeyboardEvents: true
      keydown: (event) ->
        keyChar = KeyboardUtils.getKeyChar(event)
        if /[A-Z]/.test keyChar
          exit mode, ->
            chrome.runtime.sendMessage
              handler: 'createMark'
              markName: keyChar
              scrollX: window.scrollX
              scrollY: window.scrollY
            , -> HUD.showForDuration "Created global mark '#{keyChar}'.", 1000
        else if /[a-z]/.test keyChar
          [baseLocation, sep, hash] = window.location.href.split '#'
          localStorage["vimiumMark|#{baseLocation}|#{keyChar}"] = JSON.stringify
            scrollX: window.scrollX,
            scrollY: window.scrollY
          exit mode, -> HUD.showForDuration "Created local mark '#{keyChar}'.", 1000
        else if not event.shiftKey
          exit mode

  activateGotoMode: ->
    mode = new Mode
      name: "goto-mark"
      indicator: "Go to mark?"
      suppressAllKeyboardEvents: true
      keydown: (event) ->
        keyChar = KeyboardUtils.getKeyChar(event)
        if /[A-Z]/.test keyChar
          exit mode, ->
            chrome.runtime.sendMessage
              handler: 'gotoMark'
              markName: keyChar
        else if /[a-z]/.test keyChar
          [baseLocation, sep, hash] = window.location.href.split '#'
          markString = localStorage["vimiumMark|#{baseLocation}|#{keyChar}"]
          exit mode, ->
            if markString?
              mark = JSON.parse markString
              window.scrollTo mark.scrollX, mark.scrollY
              HUD.showForDuration "Jumped to local mark '#{keyChar}'", 1000
            else
              HUD.showForDuration "Local mark not set: '#{keyChar}'.", 1000
        else if not event.shiftKey
          exit mode

root = exports ? window
root.Marks =  Marks

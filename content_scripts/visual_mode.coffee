VisualMode = 

  keyMap: ""
  isActive: false
  
  toggleVisualMode: ->
    if (@isActive) 
      @deactivateMode()
      return
    
    @isActive = true
    HUD.show("Visual Mode")
    document.body.classList.add("vimiumVisualMode")

    @handlerId = handlerStack.push({
      keydown: @onKeyDownInMode.bind(this),
      # trap all key events
      keypress: -> false
      keyup: -> false
    })
  
  onKeyDownInMode: (event) ->
    keyCode = KeyboardUtils.getKeyChar(event)

    if (KeyboardUtils.isEscape(event) || keyCode == "v") 
      @deactivateMode()

    sel = window.getSelection()
    switch keyCode
      when "h" then sel.modify("extend", "backward", "character")
      when "l" then sel.modify("extend", "forward", "character")
      
      when "k" then sel.modify("extend", "backward", "line")
      when "j" then sel.modify("extend", "forward", "line")
      when "b" then sel.modify("extend", "backward", "word")
      when "0" then sel.modify("extend", "backward", "lineboundary")
      when "e" then sel.modify("extend", "forward", "word")
      when "w" then sel.modify("extend", "forward", "word")
      when "$" then sel.modify("extend", "forward", "lineboundary")
      when "y" then @yankSelection()
      when "r" then chrome.runtime.reload()

  deactivateMode: (delay, callback) ->
    deactivate = =>
      handlerStack.remove @handlerId
      HUD.hide()
      @isActive = false
      document.body.classList.remove("vimiumVisualMode")

    # we invoke the deactivate() function directly instead of using setTimeout(callback, 0) so that
    # deactivateMode can be tested synchronously
    if (!delay)
      deactivate()
      callback() if (callback)
    else
      setTimeout(->
        deactivate()
        callback() if callback
      delay)

  yankSelection: ->
    sel = window.getSelection()
    text = sel.toString()
    @deactivateMode()
    sel.removeAllRanges()
    chrome.extension.sendMessage { handler: "copyToClipboard", data: text}

root = exports ? window
@keymap = root.settings
root.VisualMode = VisualMode 

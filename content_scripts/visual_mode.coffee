VisualMode = 

  #keyToCommandRegistry will be populated on pageload by vimium_frontend, which
  #retrieves keyToVisualModeCommandRegistry from settings
  keyToCommandRegistry: {}

  isActive: false
  freeEndToggled: false

  backwardCharacter: (sel) -> sel.modify("extend", "backward", "character")
  forwardCharacter: (sel) -> sel.modify("extend", "forward", "character")

  backwardWord: (sel) -> sel.modify("extend", "backward", "word")
  forwardWord: (sel) -> sel.modify("extend", "forward", "word")
  
  backwardLine: (sel) -> sel.modify("extend", "backward", "line")
  forwardLine: (sel) -> sel.modify("extend", "forward", "line")
  
  backwardLineBoundary: (sel) -> sel.modify(
    "extend", "backward", "lineboundary")
  forwardLineBoundary: (sel) -> sel.modify(
    "extend", "forward", "lineboundary")
  
  reload: (sel) -> chrome.runtime.reload()

  #wrap deactivateMode so that we can use the (sel) -> call signature without
  #the selection being mistaken for the delay
  deactivateModeNow: (sel) -> @deactivateMode()

  toggleVisualMode: ->
    @freeEndToggled = false
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

    #To prevent unexpected behavior, we're going to limit visual mode keybindings
    #to only triggering functions defined on the VisualMode object

    sel = window.getSelection()
    commandName = @keyToCommandRegistry[keyCode].command
    command = this[commandName]

    #find the command we want to run and run it, passing the current selection
    if typeof(command) == "function"
      command(sel)

  toggleFreeEndOfSelection: (sel) ->
    range = sel.getRangeAt(0)
    startOffset = range.startOffset
    startContainer = range.startContainer
    endOffset = range.endOffset
    endContainer = range.endContainer

    if (@freeEndToggled)
      range.setStart(startContainer, startOffset)
      sel.removeAllRanges()
      sel.addRange(range)
      sel.extend(endContainer, endOffset)
    else
      range.setStart(endContainer, endOffset)
      sel.removeAllRanges()
      sel.addRange(range)
      sel.extend(startContainer, startOffset)

    @freeEndToggled = !@freeEndToggled

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

  yankSelection: (sel) ->
    text = sel.toString()
    @deactivateMode()
    sel.removeAllRanges()
    chrome.extension.sendMessage { handler: "copyToClipboard", data: text}

root = exports ? window
root.VisualMode = VisualMode 

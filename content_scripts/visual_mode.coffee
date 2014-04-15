VisualMode = 

  #keyToCommandRegistry will be populated on mode activation, when we can
  #retrieve keyToVisualModeCommandRegistry from settings
  keyToCommandRegistry: {}

  isActive: false
  freeEndToggled: false

  #
  # To be called once settings hsa been loaded, so we can get the keybindings
  #
  init: ->
    @keyToCommandRegistry = settings.get("keyToVisualModeCommandRegistry")

  backwardCharacter: ->
    window.getSelection().modify("extend", "backward", "character")
  forwardCharacter: ->
    window.getSelection().modify("extend", "forward", "character")

  backwardWord: -> window.getSelection().modify("extend", "backward", "word")
  forwardWord: -> window.getSelection().modify("extend", "forward", "word")
  
  backwardLine: -> window.getSelection().modify("extend", "backward", "line")
  forwardLine: -> window.getSelection().modify("extend", "forward", "line")
  
  backwardLineBoundary: -> window.getSelection().modify(
    "extend", "backward", "lineboundary")
  forwardLineBoundary: -> window.getSelection().modify(
    "extend", "forward", "lineboundary")
  
  reload: -> chrome.runtime.reload()

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
    })

    #clicking anywhere deactivates visual mode
    document.addEventListener("click",
      @deactivateMode.bind(this))

    chrome.runtime.sendMessage(
      handler: "changeTabVisualMode"
      visualMode: true)
  
  onKeyDownInMode: (event) ->
    # the escape key always deactivates visual mode
    # other keys are passed on to vimium_frontend for dispatch to the
    # background key handler
    if (KeyboardUtils.isEscape(event)) 
      @deactivateMode()
      chrome.runtime.sendMessage(
        handler: "changeTabVisualMode"
        visualMode: false)
      return false

    return true

  toggleFreeEndOfSelection: ->
    sel = window.getSelection()
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
      document.removeEventListener("click",
        @deactivateMode.bind(this))
      chrome.runtime.sendMessage(
        handler: "changeTabVisualMode"
        visualMode: false)


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
    chrome.runtime.sendMessage(
      handler: "changeTabVisualMode"
      visualMode: false)

root = exports ? window
root.VisualMode = VisualMode 

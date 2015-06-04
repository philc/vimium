
Marks =
  mode: null
  previousPosition: null

  exit: (continuation = null) ->
    @mode?.exit()
    @mode = null
    continuation?()

  # This returns the key which is used for storing mark locations in localStorage.
  getLocationKey: (keyChar) ->
    "vimiumMark|#{window.location.href.split('#')[0]}|#{keyChar}"

  getMarkString: ->
    JSON.stringify scrollX: window.scrollX, scrollY: window.scrollY

  setPreviousPosition: ->
    @previousPosition = @getMarkString()

  showMessage: (message, keyChar) ->
    HUD.showForDuration "#{message} \"#{keyChar}\".", 1000

  activateCreateMode: ->
    @mode = new Mode
      name: "create-mark"
      indicator: "Create mark..."
      exitOnEscape: true
      suppressAllKeyboardEvents: true
      keypress: (event) =>
        keyChar = String.fromCharCode event.charCode
        # If <Shift> is depressed, then it's a global mark, otherwise it's a local mark.  This is consistent
        # vim's [A-Z] for global marks, [a-z] for local marks.  However, it also admits other non-Latin
        # characters.
        @exit =>
          if event.shiftKey
              chrome.runtime.sendMessage
                handler: 'createMark'
                markName: keyChar
                scrollX: window.scrollX
                scrollY: window.scrollY
              , => @showMessage "Created global mark", keyChar
          else
              localStorage[@getLocationKey keyChar] = @getMarkString()
              @showMessage "Created local mark", keyChar

  activateGotoMode: (registryEntry) ->
    # We pick off the last character of the key sequence used to launch this command. Usually this is just "`".
    # We then use that character, so together usually the sequence "``", to jump back to the previous
    # position.  The "previous position" is recorded below, and is registered via @setPreviousPosition()
    # elsewhere for various other jump-like commands.
    previousPositionKey = registryEntry.key[registryEntry.key.length-1..]
    @mode = new Mode
      name: "goto-mark"
      indicator: "Go to mark..."
      exitOnEscape: true
      suppressAllKeyboardEvents: true
      keypress: (event) =>
        @exit =>
          keyChar = String.fromCharCode event.charCode
          if event.shiftKey
            chrome.runtime.sendMessage
              handler: 'gotoMark'
              markName: keyChar
          else
            markString =
              if keyChar == previousPositionKey then @previousPosition else localStorage[@getLocationKey keyChar]
            if markString?
              @setPreviousPosition()
              position = JSON.parse markString
              window.scrollTo position.scrollX, position.scrollY
              @showMessage "Jumped to local mark", keyChar
            else
              @showMessage "Local mark not set", keyChar

root = exports ? window
root.Marks =  Marks

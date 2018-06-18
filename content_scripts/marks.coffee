
Marks =
  previousPositionRegisters: [ "`", "'" ]
  localRegisters: {}
  currentRegistryEntry: null
  mode: null

  exit: (continuation = null) ->
    @mode?.exit()
    @mode = null
    continuation?()

  # This returns the key which is used for storing mark locations in localStorage.
  getLocationKey: (keyChar) ->
    "vimiumMark|#{window.location.href.split('#')[0]}|#{keyChar}"

  getMarkString: ->
    JSON.stringify scrollX: window.scrollX, scrollY: window.scrollY, hash: window.location.hash

  setPreviousPosition: ->
    markString = @getMarkString()
    @localRegisters[reg] = markString for reg in @previousPositionRegisters

  showMessage: (message, keyChar) ->
    HUD.showForDuration "#{message} \"#{keyChar}\".", 1000

  # If <Shift> is depressed, then it's a global mark, otherwise it's a local mark.  This is consistent
  # vim's [A-Z] for global marks and [a-z] for local marks.  However, it also admits other non-Latin
  # characters.  The exceptions are "`" and "'", which are always considered local marks.
  # The "swap" command option inverts global and local marks.
  isGlobalMark: (event, keyChar) ->
    shiftKey = event.shiftKey
    shiftKey = not shiftKey if @currentRegistryEntry.options.swap
    shiftKey and keyChar not in @previousPositionRegisters

  activateCreateMode: (count, {registryEntry}) ->
    @currentRegistryEntry = registryEntry
    @mode = new Mode
      name: "create-mark"
      indicator: "Create mark..."
      exitOnEscape: true
      suppressAllKeyboardEvents: true
      keydown: (event) =>
        if KeyboardUtils.isPrintable event
          keyChar = KeyboardUtils.getKeyChar event
          @exit =>
            if @isGlobalMark event, keyChar
              # We record the current scroll position, but only if this is the top frame within the tab.
              # Otherwise, we'll fetch the scroll position of the top frame from the background page later.
              [ scrollX, scrollY ] = [ window.scrollX, window.scrollY ] if DomUtils.isTopFrame()
              chrome.runtime.sendMessage
                handler: 'createMark'
                markName: keyChar
                scrollX: scrollX
                scrollY: scrollY
              , => @showMessage "Created global mark", keyChar
            else
              localStorage[@getLocationKey keyChar] = @getMarkString()
              @showMessage "Created local mark", keyChar
          handlerStack.suppressEvent

  activateGotoMode: (count, {registryEntry}) ->
    @currentRegistryEntry = registryEntry
    @mode = new Mode
      name: "goto-mark"
      indicator: "Go to mark..."
      exitOnEscape: true
      suppressAllKeyboardEvents: true
      keydown: (event) =>
        if KeyboardUtils.isPrintable event
          @exit =>
            keyChar = KeyboardUtils.getKeyChar event
            if @isGlobalMark event, keyChar
              # This key must match @getLocationKey() in the back end.
              key = "vimiumGlobalMark|#{keyChar}"
              Settings.storage.get key, (items) ->
                if key of items
                  chrome.runtime.sendMessage handler: 'gotoMark', markName: keyChar
                  HUD.showForDuration "Jumped to global mark '#{keyChar}'", 1000
                else
                  HUD.showForDuration "Global mark not set '#{keyChar}'", 1000
            else
              markString = @localRegisters[keyChar] ? localStorage[@getLocationKey keyChar]
              if markString?
                @setPreviousPosition()
                position = JSON.parse markString
                if position.hash and position.scrollX == 0 and position.scrollY == 0
                  window.location.hash = position.hash
                else
                  window.scrollTo position.scrollX, position.scrollY
                @showMessage "Jumped to local mark", keyChar
              else
                @showMessage "Local mark not set", keyChar
          handlerStack.suppressEvent

root = exports ? (window.root ?= {})
root.Marks =  Marks
extend window, root unless exports?

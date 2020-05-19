
class InsertMode extends Mode
  constructor: (options = {}) ->
    super()
    # There is one permanently-installed instance of InsertMode.  It tracks focus changes and
    # activates/deactivates itself (by setting @insertModeLock) accordingly.
    @permanent = options.permanent

    # If truthy, then we were activated by the user (with "i").
    @global = options.global

    handleKeyEvent = (event) =>
      unless @isActive event
        return @continueBubbling

      # See comment here: https://github.com/philc/vimium/commit/48c169bd5a61685bb4e67b1e76c939dbf360a658.
      activeElement = @getActiveElement()
      if activeElement == document.body and activeElement.isContentEditable
        return @passEventToPage

      # Check for a pass-next-key key.
      keyString = KeyboardUtils.getKeyCharString(event)
      if keyString in Settings.get "passNextKeyKeys"
        new PassNextKeyMode

      else if event.type == 'keydown' and KeyboardUtils.isEscape(event)
        activeElement.blur() if DomUtils.isFocusable activeElement
        unless @permanent
          @exit()

      else
        return @passEventToPage

      return @suppressEvent

    defaults =
      name: "insert"
      indicator: if not @permanent and not Settings.get "hideHud"  then "Insert mode"
      keypress: handleKeyEvent
      keydown: handleKeyEvent

    super.init(extend(defaults, options))

    # Only for tests.  This gives us a hook to test the status of the permanently-installed instance.
    if @permanent
      InsertMode.permanentInstance = this

  isActive: (event) ->
    if event == InsertMode.suppressedEvent
      return false
    if @global
      return true
    DomUtils.isFocusable @getActiveElement()

  getActiveElement: ->
    activeElement = document.activeElement
    while activeElement && activeElement.shadowRoot && activeElement.shadowRoot.activeElement
      activeElement = activeElement.shadowRoot.activeElement
    activeElement

  @suppressEvent: (event) -> @suppressedEvent = event; return

# This allows PostFindMode to suppress the permanently-installed InsertMode instance.
InsertMode.suppressedEvent = null

# This implements the pasNexKey command.
class PassNextKeyMode extends Mode
  constructor: (count = 1) ->
    super()
    seenKeyDown = false
    keyDownCount = 0

    super.init
      name: "pass-next-key"
      indicator: "Pass next key."
      # We exit on blur because, once we lose the focus, we can no longer track key events.
      exitOnBlur: window
      keypress: =>
        @passEventToPage

      keydown: =>
        seenKeyDown = true
        keyDownCount += 1
        @passEventToPage

      keyup: =>
        if seenKeyDown
          unless --keyDownCount > 0
            unless --count > 0
              @exit()
        @passEventToPage

root = exports ? (window.root ?= {})
root.InsertMode = InsertMode
root.PassNextKeyMode = PassNextKeyMode
extend window, root unless exports?

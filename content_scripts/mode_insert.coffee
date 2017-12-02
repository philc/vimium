
class InsertMode extends Mode
  constructor: (options = {}) ->
    # There is one permanently-installed instance of InsertMode.  It tracks focus changes and
    # activates/deactivates itself (by setting @insertModeLock) accordingly.
    @permanent = options.permanent

    # If truthy, then we were activated by the user (with "i").
    @global = options.global

    handleKeyEvent = (event) =>
      return @continueBubbling unless @isActive event

      # See comment here: https://github.com/philc/vimium/commit/48c169bd5a61685bb4e67b1e76c939dbf360a658.
      activeElement = @getActiveElement()
      return @passEventToPage if activeElement == document.body and activeElement.isContentEditable

      # Check for a pass-next-key key.
      if KeyboardUtils.getKeyCharString(event) in Settings.get "passNextKeyKeys"
        new PassNextKeyMode

      else if event.type == 'keydown' and KeyboardUtils.isEscape(event)
        activeElement.blur() if DomUtils.isFocusable activeElement
        @exit() unless @permanent

      else
        return @passEventToPage

      return @suppressEvent

    defaults =
      name: "insert"
      indicator: if not @permanent and not Settings.get "hideHud"  then "Insert mode"
      keypress: handleKeyEvent
      keydown: handleKeyEvent

    super extend defaults, options

    # Only for tests.  This gives us a hook to test the status of the permanently-installed instance.
    InsertMode.permanentInstance = this if @permanent

  isActive: (event) ->
    return false if event == InsertMode.suppressedEvent
    return true if @global
    DomUtils.isFocusable @getActiveElement()

  getActiveElement: ->
    activeElement = document.activeElement
    while activeElement?.shadowRoot?.activeElement
      activeElement = activeElement.shadowRoot.activeElement
    activeElement

  # Static stuff. This allows PostFindMode to suppress the permanently-installed InsertMode instance.
  @suppressedEvent: null
  @suppressEvent: (event) -> @suppressedEvent = event

# This implements the pasNexKey command.
class PassNextKeyMode extends Mode
  constructor: (count = 1) ->
    seenKeyDown = false
    keyDownCount = 0

    super
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
          unless 0 < --keyDownCount
            unless 0 < --count
              @exit()
        @passEventToPage

root = exports ? (window.root ?= {})
root.InsertMode = InsertMode
root.PassNextKeyMode = PassNextKeyMode
extend window, root unless exports?

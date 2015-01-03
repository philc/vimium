
class Mode
  # Static members.
  @modes: []
  @current: -> Mode.modes[0]

  # Constants; readable shortcuts for event-handler return values.
  continueBubbling: true
  suppressEvent: false
  stopBubblingAndTrue: handlerStack.stopBubblingAndTrue
  stopBubblingAndFalse: handlerStack.stopBubblingAndFalse

  # Default values.
  name: ""             # The name of this mode.
  badge: ""            # A badge to display on the popup when this mode is active.
  keydown: "suppress"  # A function, or "suppress", "bubble" or "pass"; see checkForBuiltInHandler().
  keypress: "suppress" # A function, or "suppress", "bubble" or "pass"; see checkForBuiltInHandler().
  keyup: "suppress"    # A function, or "suppress", "bubble" or "pass"; see checkForBuiltInHandler().

  constructor: (options) ->
    extend @, options

    @handlers = []
    @handlers.push handlerStack.push
      keydown: @checkForBuiltInHandler "keydown", @keydown
      keypress: @checkForBuiltInHandler "keypress", @keypress
      keyup: @checkForBuiltInHandler "keyup", @keyup
      updateBadgeForMode: (badge) => @updateBadgeForMode badge

    Mode.modes.unshift @

  # Allow the strings "suppress" and "pass" to be used as proxies for the built-in handlers.
  checkForBuiltInHandler: (type, handler) ->
    switch handler
      when "suppress" then @generateHandler type, @suppressEvent
      when "bubble" then @generateHandler type, @continueBubbling
      when "pass" then @generateHandler type, @stopBubblingAndTrue
      else handler

  # Generate a default handler which always always yields the same result; except Esc, which pops the current
  # mode.
  generateHandler: (type, result) ->
    (event) =>
      return result unless type == "keydown" and KeyboardUtils.isEscape event
      @exit()
      @suppressEvent

  exit: ->
    handlerStack.remove handlerId for handlerId in @handlers
    Mode.modes = Mode.modes.filter (mode) => mode != @
    Mode.updateBadge()

  # Default updateBadgeForMode handler.  This is overridden by sub-classes.  The default is to install the
  # current mode's badge, unless the bade is already set.
  updateBadgeForMode: (badge) ->
    handlerStack.alwaysContinueBubbling => badge.badge ||= @badge

  # Static method.  Used externally and internally to initiate bubbling of an updateBadgeForMode event.
  # Do not update the badge:
  #   - if this document does not have the focus, or
  #   - if the document's body is a frameset
  @updateBadge: ->
    if document.hasFocus()
      unless document.body?.tagName.toLowerCase() == "frameset"
        badge = {badge: ""}
        handlerStack.bubbleEvent "updateBadgeForMode", badge
        Mode.sendBadge badge.badge

  # Static utility to update the browser-popup badge.
  @sendBadge: (badge) ->
    chrome.runtime.sendMessage({ handler: "setBadge", badge: badge })

  # Install a mode, call a function, and exit the mode again.
  @runIn: (mode, func) ->
    mode = new mode()
    func()
    mode.exit()

root = exports ? window
root.Mode = Mode

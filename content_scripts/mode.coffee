
class Mode
  # Static members.
  @modes: []
  @current: -> Mode.modes[0]

  # Constants. Static.
  @suppressPropagation = false
  @propagate = true

  # Default values.
  name: ""             # The name of this mode.
  badge: ""            # A badge to display on the popup when this mode is active.
  keydown: "suppress"  # A function, or "suppress" or "pass"; the latter are replaced with suitable functions.
  keypress: "suppress" # A function, or "suppress" or "pass"; the latter are replaced with suitable functions.
  keyup: "suppress"    # A function, or "suppress" or "pass"; the latter are replaced with suitable functions.

  constructor: (options) ->
    extend @, options

    @handlerId = handlerStack.push
      keydown: @checkForBuiltInHandler "keydown", @keydown
      keypress: @checkForBuiltInHandler "keypress", @keypress
      keyup: @checkForBuiltInHandler "keyup", @keyup

    Mode.modes.unshift @
    Mode.setBadge()

  # Allow the strings "suppress" and "pass" to be used as proxies for the built-in handlers.
  checkForBuiltInHandler: (type, handler) ->
    switch handler
      when "suppress" then @generateSuppressPropagation type
      when "pass" then @generatePassThrough type
      else handler

  # Generate a default handler which always passes through to the underlying page; except Esc, which pops the
  # current mode.
  generatePassThrough: (type) ->
    (event) =>
      if type == "keydown" and KeyboardUtils.isEscape event
        @exit()
        return Mode.suppressPropagation
      handlerStack.passDirectlyToPage

  # Generate a default handler which always suppresses propagation; except Esc, which pops the current mode.
  generateSuppressPropagation: (type) ->
    handler = @generatePassThrough type
    (event) -> handler(event) and Mode.suppressPropagation # Always falsy.

  exit: ->
    handlerStack.remove @handlerId
    Mode.modes = Mode.modes.filter (mode) => mode != @
    Mode.setBadge()

  # Set the badge on the browser popup to indicate the current mode; static method.
  @setBadge: ->
    chrome.runtime.sendMessage({ handler: "setBadge", badge: Mode.getBadge() })

  # Static convenience methods.
  @is: (mode) -> Mode.current()?.name == mode
  @getBadge: -> Mode.current()?.badge || ""
  @isInsert: -> Mode.is "insert"

root = exports ? window
root.Mode = Mode

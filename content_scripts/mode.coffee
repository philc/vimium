
class Mode
  # Static members.
  @modes: []
  @current: -> Mode.modes[0]
  @suppressPropagation = false
  @propagate = true

  # Default values.
  name: ""             # The name of this mode.
  badge: ""            # A badge to display on the popup when this mode is active.
  keydown: "suppress"  # A function, or "suppress" or "pass"; the latter are replaced with suitable functions.
  keypress: "suppress" # A function, or "suppress" or "pass"; the latter are replaced with suitable functions.
  keyup: "suppress"    # A function, or "suppress" or "pass"; the latter are replaced with suitable functions.
  onDeactivate: ->     # Called when leaving this mode.
  onReactivate: ->     # Called when this mode is reactivated.

  constructor: (options) ->
    extend @, options

    @handlerId = handlerStack.push
      keydown: @checkForBuiltInHandler "keydown", @keydown
      keypress: @checkForBuiltInHandler "keypress", @keypress
      keyup: @checkForBuiltInHandler "keyup", @keyup
      reactivateMode: =>
        @onReactivate()
        Mode.setBadge()
        return Mode.suppressPropagation

    Mode.modes.unshift @
    Mode.setBadge()

  # Allow the strings "suppress" and "pass" to be used as proxies for the built-in handlers.
  checkForBuiltInHandler: (type, handler) ->
    switch handler
      when "suppress" then @generateSuppressPropagation type
      when "pass" then @generatePassThrough type
      else handler

  # Generate a default handler which always passes through; except Esc, which pops the current mode.
  generatePassThrough: (type) ->
    me = @
    (event) ->
      if type == "keydown" and KeyboardUtils.isEscape event
        me.popMode event
        return Mode.suppressPropagation
      handlerStack.passThrough

  # Generate a default handler which always suppresses propagation; except Esc, which pops the current mode.
  generateSuppressPropagation: (type) ->
    handler = @generatePassThrough type
    (event) -> handler(event) and Mode.suppressPropagation # Always falsy.

  # Leave the current mode; event may or may not be provide.  It is the responsibility of the creator of this
  # object to know whether or not an event will be provided.  Bubble a "reactivateMode" event to notify the
  # now-active mode that it is once again top dog.
  popMode: (event) ->
    Mode.modes = Mode.modes.filter (mode) => mode != @
    handlerStack.remove @handlerId
    @onDeactivate event
    handlerStack.bubbleEvent "reactivateMode", event

  # Set the badge on the browser popup to indicate the current mode; static method.
  @setBadge: ->
    badge = Mode.getBadge()
    chrome.runtime.sendMessage({ handler: "setBadge", badge: badge })

  # Static convenience methods.
  @is: (mode) -> Mode.current()?.name == mode
  @getBadge: -> Mode.current()?.badge || ""
  @isInsert: -> Mode.is "insert"

root = exports ? window
root.Mode = Mode

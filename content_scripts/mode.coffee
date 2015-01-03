
count = 0

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
  name: ""
  badge: ""
  keydown: (event) => @continueBubbling
  keypress: (event) => @continueBubbling
  keyup: (event) => @continueBubbling

  constructor: (options) ->
    Mode.modes.unshift @
    extend @, options
    @count = ++count
    console.log @count, "create:", @name

    @handlers = []
    @handlers.push handlerStack.push
      keydown: @keydown
      keypress: @keypress
      keyup: @keyup
      updateBadge: (badge) => handlerStack.alwaysContinueBubbling => @chooseBadge badge

  exit: ->
    console.log @count, "exit:", @name
    handlerStack.remove handlerId for handlerId in @handlers
    Mode.modes = Mode.modes.filter (mode) => mode != @
    Mode.updateBadge()

  # The badge is chosen by bubbling an "updateBadge" event down the handler stack allowing each mode the
  # opportunity to choose a badge.  chooseBadge, here, is the default: choose the current mode's badge unless
  # one has already been chosen.  This is overridden in sub-classes.
  chooseBadge: (badge) ->
    badge.badge ||= @badge

  # Static method.  Used externally and internally to initiate bubbling of an updateBadge event and to send
  # the resulting badge to the background page.  We only update the badge if this document has the focus, and
  # the document's body isn't a frameset.
  @updateBadge: ->
    if document.hasFocus()
      unless document.body?.tagName.toLowerCase() == "frameset"
        badge = {badge: ""}
        handlerStack.bubbleEvent "updateBadge", badge
        chrome.runtime.sendMessage({ handler: "setBadge", badge: badge.badge })

  # Temporarily install a mode.
  @runIn: (mode, func) ->
    mode = new mode()
    func()
    mode.exit()

# A SingletonMode is a Mode of which there may be at most one instance (of @singleton) active at any one time.
# New instances cancel previous instances on startup.
class SingletonMode extends Mode
  @instances: {}

  exit: ->
    delete SingletonMode[@singleton]
    super()

  constructor: (@singleton, options={}) ->
    SingletonMode[@singleton].exit() if SingletonMode[@singleton]
    SingletonMode[@singleton] = @
    super options

# MultiMode is a collection of modes which are installed or uninstalled together.
class MultiMode extends Mode
  constructor: (modes...) ->
    @modes = (new mode() for mode in modes)
    super {name: "multimode"}

  exit: ->
    mode.exit() for mode in modes

root = exports ? window
root.Mode = Mode
root.SingletonMode = SingletonMode
root.MultiMode = MultiMode

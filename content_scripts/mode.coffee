# Modes.
#
# A mode implements a number of event handlers which are pushed onto the handler stack when the mode starts,
# and poped when the mode exits.  The Mode base takes as single argument options which can defined:
#
# name:
#   A name for this mode.
#
# badge:
#   A badge (to appear on the browser popup) for this mode.
#   Optional.  Define a badge is the badge is constant.  Otherwise, do not set a badge and override the
#   chooseBadge method instead.  Or, if the mode *never* shows a bade, then do neither.
#
# keydown:
# keypress:
# keyup:
#   Key handlers.  Optional: provide these as required.  The default is to continue bubbling all key events.
#
# Additional handlers associated with the mode can be added by using the push method.  For example, if a mode
# responds to "focus" events, then push an additional handler:
#   @push
#     "focus": (event) => ....
# Any such additional handlers are removed when the mode exits.
#
# New mode types are created by inheriting from Mode or one of its sub-classes.  Some generic cub-classes are
# provided below:
#   SingletonMode: ensures that at most one instance of the mode should be active at any time.
#   ConstrainedMode: exits the mode if the user clicks outside of the given element.
#   ExitOnEscapeMode: exits the mode if the user types Esc.
#   StateMode: tracks the current Vimium state in @enabled and @passKeys.
#
# To install and existing mode, use:
#   myMode = new MyMode()
#
# To remove a mode, use:
#   myMode.exit() # externally triggered.
#   @exit()       # internally triggered (more common).
#

# Debug only; to be stripped out.
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
  keydown: null
  keypress: null
  keyup: null

  constructor: (options={}) ->
    Mode.modes.unshift @
    extend @, options
    @modeIsActive = true
    @count = ++count
    console.log @count, "create:", @name

    @handlers = []
    @push
      keydown: @keydown
      keypress: @keypress
      keyup: @keyup
      updateBadge: (badge) => handlerStack.alwaysContinueBubbling => @chooseBadge badge

  push: (handlers) ->
    @handlers.push handlerStack.push handlers

  exit: ->
    if @modeIsActive
      console.log @count, "exit:", @name
      # We reverse @handlers, here.  That way, handlers are popped in the opposite order to that in which they
      # were pushed.
      handlerStack.remove handlerId for handlerId in @handlers.reverse()
      Mode.modes = Mode.modes.filter (mode) => mode != @
      Mode.updateBadge()
      @modeIsActive = false

  # The badge is chosen by bubbling an "updateBadge" event down the handler stack allowing each mode the
  # opportunity to choose a badge.  chooseBadge, here, is the default: choose the current mode's badge unless
  # one has already been chosen.  This is overridden in sub-classes.
  chooseBadge: (badge) ->
    badge.badge ||= @badge

  # Static method.  Used externally and internally to initiate bubbling of an updateBadge event and to send
  # the resulting badge to the background page.  We only update the badge if this document has the focus.
  @updateBadge: ->
    if document.hasFocus()
      handlerStack.bubbleEvent "updateBadge", badge = {badge: ""}
      chrome.runtime.sendMessage
        handler: "setBadge"
        badge: badge.badge

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
    delete SingletonMode.instances[@singleton]
    super()

  constructor: (@singleton, options={}) ->
    SingletonMode.kill @singleton
    SingletonMode.instances[@singleton] = @
    super options

  # Static method. If there's a singleton instance running, then kill it.
  @kill: (singleton) ->
    SingletonMode.instances[singleton].exit() if SingletonMode.instances[singleton]

# The mode exits when the user hits Esc.
class ExitOnEscapeMode extends SingletonMode
  constructor: (singleton, options) ->
    super singleton, options

    # This handler ends up above the mode's own key handlers on the handler stack, so it takes priority.
    @push
      "keydown": (event) =>
        return @continueBubbling unless KeyboardUtils.isEscape event
        @exit
          source: ExitOnEscapeMode
          event: event
        @suppressEvent

# When @element loses the focus.
class ConstrainedMode extends ExitOnEscapeMode
  constructor: (@element, singleton, options) ->
    super singleton, options

    if @element
      @element.focus()
      @push
        "blur": (event) =>
          handlerStack.alwaysContinueBubbling =>
            @exit() if event.srcElement == @element

# The state mode tracks the enabled state in @enabled and @passKeys, and its initialized state in
# @initialized.  It calls @registerStateChange() whenever the state changes.
class StateMode extends Mode
  constructor: (options) ->
    @stateInitialized = false
    @enabled = false
    @passKeys = ""
    super options

    @push
      "registerStateChange": ({enabled: enabled, passKeys: passKeys}) =>
        handlerStack.alwaysContinueBubbling =>
          if enabled != @enabled or passKeys != @passKeys or not @stateInitialized
            @stateInitialized = true
            @enabled = enabled
            @passKeys = passKeys
            @registerStateChange()

  # Overridden by sub-classes.
  registerStateChange: ->

# BadgeMode is a psuedo mode for managing badge updates on focus changes and state updates. It sits at the
# bottom of the handler stack, and so it receives state changes *after* all other modes.
class BadgeMode extends StateMode
  constructor: (options) ->
    options.name ||= "badge"
    super options

    @push
      "focus": =>
        handlerStack.alwaysContinueBubbling =>
          Mode.updateBadge()

  chooseBadge: (badge) ->
    # If we're not enabled, then post an empty badge (so, no badge at all).
    badge.badge = "" unless @enabled

  registerStateChange: ->
    Mode.updateBadge()

# Install a single BadgeMode instance.
new BadgeMode {}

root = exports ? window
root.Mode = Mode
root.SingletonMode = SingletonMode
root.ConstrainedMode = ConstrainedMode
root.StateMode = StateMode
root.ExitOnEscapeMode = ExitOnEscapeMode

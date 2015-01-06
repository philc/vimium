# Modes.
#
# A mode implements a number of keyboard event handlers which are pushed onto the handler stack when the mode
# starts, and poped when the mode exits.  The Mode base class takes as single argument options which can
# define:
#
# name:
#   A name for this mode.
#
# badge:
#   A badge (to appear on the browser popup) for this mode.
#   Optional.  Define a badge is the badge is constant.  Otherwise, do not define a badge and override the
#   chooseBadge method instead.  Or, if the mode *never* shows a badge, then do neither.
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
#
#   SingletonMode: ensures that at most one instance of the mode is active at any one time.
#   ConstrainedMode: exits the mode if the an indicated element loses the focus.
#   ExitOnEscapeMode: exits the mode on escape.
#   StateMode: tracks the current Vimium state in @enabled and @passKeys.
#
# To install and existing mode, use:
#   myMode = new MyMode()
#
# To remove a mode, use:
#   myMode.exit() # externally triggered.
#   @exit()       # internally triggered (more common).
#

# For debug only; to be stripped out.
count = 0

class Mode
  # Static.
  @modes: []

  # Constants; readable shortcuts for event-handler return values.
  continueBubbling: true
  suppressEvent: false
  stopBubblingAndTrue: handlerStack.stopBubblingAndTrue
  stopBubblingAndFalse: handlerStack.stopBubblingAndFalse

  # Default values.
  name: ""
  badge: ""
  keydown: null # null will be ignored by handlerStack (so it's a safe default).
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
      updateBadge: (badge) => @alwaysContinueBubbling => @chooseBadge badge

    Mode.updateBadge() if @badge

  push: (handlers) ->
    @handlers.push handlerStack.push handlers

  exit: ->
    if @modeIsActive
      console.log @count, "exit:", @name
      handlerStack.remove handlerId for handlerId in @handlers
      Mode.modes = Mode.modes.filter (mode) => mode != @
      Mode.updateBadge()
      @modeIsActive = false

  # The badge is chosen by bubbling an "updateBadge" event down the handler stack allowing each mode the
  # opportunity to choose a badge.  chooseBadge, here, is the default. It is overridden in sub-classes.
  chooseBadge: (badge) ->
    badge.badge ||= @badge

  # Shorthand for a long name.
  alwaysContinueBubbling: (func) -> handlerStack.alwaysContinueBubbling func

  # Static method.  Used externally and internally to initiate bubbling of an updateBadge event and to send
  # the resulting badge to the background page.  We only update the badge if this document (hence this frame)
  # has the focus.
  @updateBadge: ->
    if document.hasFocus()
      handlerStack.bubbleEvent "updateBadge", badge = {badge: ""}
      chrome.runtime.sendMessage
        handler: "setBadge"
        badge: badge.badge

  # Temporarily install a mode to call a function.
  @runIn: (mode, func) ->
    mode = new mode()
    func()
    mode.exit()

# A SingletonMode is a Mode of which there may be at most one instance (of @singleton) active at any one time.
# New instances cancel previously-active instances on startup.
class SingletonMode extends Mode
  @instances: {}

  exit: ->
    delete SingletonMode.instances[@singleton] if @singleton?
    super()

  constructor: (@singleton, options={}) ->
    if @singleton?
      SingletonMode.kill @singleton
      SingletonMode.instances[@singleton] = @
    super options

  # Static method. Return whether the indicated mode (singleton) is currently active or not.
  @isActive: (singleton) ->
    @instances[singleton]?

  # Static method. If there's a singleton instance active, then kill it.
  @kill: (singleton) ->
    SingletonMode.instances[singleton].exit() if SingletonMode.instances[singleton]

# This mode exits when the user hits Esc.
class ExitOnEscapeMode extends SingletonMode
  constructor: (singleton, options) ->
    super singleton, options

    # NOTE. This handler ends up above the mode's own key handlers on the handler stack, so it takes priority.
    @push
      "keydown": (event) =>
        return @continueBubbling unless KeyboardUtils.isEscape event
        @exit
          source: ExitOnEscapeMode
          event: event
        @suppressEvent

# This mode exits when @constrainingElement (if defined) loses the focus.
class ConstrainedMode extends ExitOnEscapeMode
  constructor: (@constrainingElement, singleton, options) ->
    super singleton, options

    if @constrainingElement
      @constrainingElement.focus()
      @push
        "blur": (event) => @alwaysContinueBubbling =>
          @exit() if event.srcElement == @constrainingElement

# The state mode tracks the enabled state in @enabled and @passKeys.  It calls @registerStateChange() whenever
# the state changes.  The state is distributed by bubbling a "registerStateChange" event down the handler
# stack.
class StateMode extends Mode
  constructor: (options) ->
    @enabled = false
    @passKeys = ""
    super options

    @push
      "registerStateChange": ({enabled: enabled, passKeys: passKeys}) =>
        @alwaysContinueBubbling =>
          if enabled != @enabled or passKeys != @passKeys
            @enabled = enabled
            @passKeys = passKeys
            @registerStateChange()

  # Overridden by sub-classes.
  registerStateChange: ->

# BadgeMode is a psuedo mode for triggering badge updates on focus changes and state updates. It sits at the
# bottom of the handler stack, and so it receives state changes *after* all other modes, and can override the
# badge choices of all other modes.
new class BadgeMode extends StateMode
  constructor: (options) ->
    super
      name: "badge"

    @push
      "focus": => @alwaysContinueBubbling => Mode.updateBadge()

  chooseBadge: (badge) ->
    # If we're not enabled, then post an empty badge.
    badge.badge = "" unless @enabled

  registerStateChange: ->
    Mode.updateBadge()

root = exports ? window
root.Mode = Mode
root.SingletonMode = SingletonMode
root.ConstrainedMode = ConstrainedMode
root.StateMode = StateMode
root.ExitOnEscapeMode = ExitOnEscapeMode

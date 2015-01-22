
# This prevents printable characters from being passed through to underlying page.  It should, however, allow
# through chrome keyboard shortcuts.  It's a backstop for all of the modes following.
class SuppressPrintable extends Mode
  constructor: (options) ->

    handler = (event) =>
      if KeyboardUtils.isPrintable event
        if event.type == "keydown"
          DomUtils.suppressPropagation
          @stopBubblingAndTrue
        else
          @suppressEvent
      else
        @stopBubblingAndTrue

    # This is pushed onto the handler stack before calling super().  Therefore, it ends up underneath (or
    # after) all of the other handlers associated with the mode.
    @suppressPrintableHandlerId = handlerStack.push
      _name: "movement/suppress-printable"
      keydown: handler
      keypress: handler
      keyup: handler

    super options
    @onExit => handlerStack.remove @suppressPrintableHandlerId

# This watches keyboard events and maintains @countPrefix as count and other keys are pressed.
class MaintainCount extends SuppressPrintable
  constructor: (options) ->
    @countPrefix = ""
    super options

    @push
      _name: "movement/maintain-count"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            @countPrefix =
              if keyChar and keyChar.length == 1 and "0" <= keyChar <= "9"
                @countPrefix + keyChar
              else
                ""

  runCountPrefixTimes: (func) ->
    count = if 0 < @countPrefix.length then parseInt @countPrefix else 1
    func() for [0...count]

# This implements movement commands with count prefixes (using MaintainCount) for visual and edit modes.
class Movement extends MaintainCount

  other:
    forward: "backward"
    backward: "forward"

  # Try to move one character in "direction".  Return 1, -1 or 0, indicating that the selection got bigger or
  # smaller, or is unchanged.
  moveInDirection: (direction, selection = window.getSelection()) ->
    length = selection.toString().length
    selection.modify "extend", direction, "character"
    selection.toString().length - length

  # Get the direction of the selection, either "forward" or "backward".
  # FIXME(smblott).  There has to be a better way!
  getDirection: (selection = window.getSelection()) ->
    # Try to move the selection forward, then check whether it got bigger or smaller (then restore it).
    success = @moveInDirection "forward", selection
    if success
      @moveInDirection "backward", selection
      return if success < 0 then "backward" else "forward"

    # If we can't move forward, we could be at the end of the document, so try moving backward instead.
    success = @moveInDirection "backward", selection
    if success
      @moveInDirection "forward", selection
      return if success < 0 then "forward" else "backward"

    "none"

  nextCharacter: (direction) ->
    if @moveInDirection direction
      text = window.getSelection().toString()
      @moveInDirection @other[direction]
      console.log text.charAt(if direction == "forward" then text.length - 1 else 0)
      text.charAt(if @getDirection() == "forward" then text.length - 1 else 0)

  moveByWord: (direction) ->
    # We go to the end of the next word, then come back to the start of it.
    movements = [ "#{direction} word", "#{@other[direction]} word" ]
    # If we're in the middle of a word, then we need to first skip over it.
    console.log @nextCharacter direction
    switch direction
      when "forward"
        movements.unshift "#{direction} word" unless /\s/.test @nextCharacter direction
      when "backward"
        movements.push "#{direction} word" unless /\s/.test @nextCharacter direction
    console.log movements
    @runMovements movements

  runMovement: (movement) ->
    window.getSelection().modify @alterMethod, movement.split(" ")...

  runMovements: (movements) ->
    for movement in movements
      @runMovement movement

  movements:
    "l": "forward character"
    "h": "backward character"
    "j": "forward line"
    "k": "backward line"
    "e": "forward word"
    "b": "backward word"
    ")": "forward sentence"
    "(": "backward sentence"
    "}": "forward paragraph"
    "{": "backward paragraph"
    "$": "forward lineboundary"
    "0": "backward lineboundary"
    "G": "forward documentboundary"
    "g": "backward documentboundary"

    "w": -> @moveByWord "forward"
    "W": -> @moveByWord "backward"

    "o": ->
      selection = window.getSelection()
      length = selection.toString().length
      switch @getDirection selection
        when "forward"
          selection.collapseToEnd()
          selection.modify "extend", "backward", "character" for [0...length]
        when "backward"
          selection.collapseToStart()
          selection.modify "extend", "forward", "character" for [0...length]

  # TODO(smblott). What do we do if there is no initial selection?  Or multiple ranges?
  constructor: (options) ->
    @alterMethod = options.alterMethod || "extend"
    super options

    @push
      _name: "movement"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            if @movements[keyChar]
              @runCountPrefixTimes =>
                switch typeof @movements[keyChar]
                  when "string"
                    @runMovement @movements[keyChar]
                  when "function"
                    @movements[keyChar].call @

class VisualMode extends Movement
  constructor: (options = {}) ->
    defaults =
      name: "visual"
      badge: "V"
      exitOnEscape: true
      exitOnBlur: options.targetElement
      alterMethod: "extend"

      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            switch String.fromCharCode event.charCode
              when "y"
                chrome.runtime.sendMessage
                  handler: "copyToClipboard"
                  data: window.getSelection().toString()
                @exit()
                # TODO(smblott). Suppress next keyup.

    super extend defaults, options
    @debug = true

class EditMode extends Movement
  @activeElements = []

  constructor: (options = {}) ->
    defaults =
      name: "edit"
      exitOnEscape: true
      alterMethod: "move"
      keydown: (event) => if @isActive() then @handleKeydown event else @continueBubbling
      keypress: (event) => if @isActive() then @handleKeypress event else @continueBubbling
      keyup: (event) => if @isActive() then @handleKeyup event else @continueBubbling

    @element = document.activeElement
    if @element and DomUtils.isEditable @element
      super extend defaults, options

  handleKeydown: (event) ->
    @stopBubblingAndTrue
  handleKeypress: (event) ->
    @suppressEvent
  handleKeyup: (event) ->
    @stopBubblingAndTrue

  isActive: ->
    document.activeElement and DomUtils.isDOMDescendant @element, document.activeElement

  exit: (event, target) ->
    super()
    @element.blur() if target? and DomUtils.isDOMDescendant @element, target
    EditMode.activeElements = EditMode.activeElements.filter (element) => element != @element

  updateBadge: (badge) ->
    badge.badge = "E" if @isActive()

root = exports ? window
root.VisualMode = VisualMode
root.EditMode = EditMode

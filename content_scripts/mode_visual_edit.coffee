
# This prevents printable characters from being passed through to underlying page.  It should, however, allow
# through chrome keyboard shortcuts.  It's a backstop for all of the modes following.
class SuppressPrintable extends Mode
  constructor: (options) ->

    handler = (event) =>
      if KeyboardUtils.isPrintable event
        if event.type == "keydown"
          # Completely suppress Backspace and Delete.
          if event.keyCode in [ 8, 46 ]
            @suppressEvent
          else
            DomUtils.suppressPropagation
            @stopBubblingAndFalse
        else
          false
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

# This watches keyboard events and maintains @countPrefix as number and other keys are pressed.
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

forward = "forward"
backward = "backward"
character = "character"

# This implements movement commands with count prefixes (using MaintainCount) for both visual mode and edit
# mode.
class Movement extends MaintainCount

  opposite:
    forward: backward
    backward: forward

  # Call a function.  Return true if the selection changed.
  selectionChanged: (func) ->
    r = @selection.getRangeAt(0).cloneRange()
    func()
    rr = @selection.getRangeAt(0)
    not (r.compareBoundaryPoints(Range.END_TO_END, rr) and r.compareBoundaryPoints Range.START_TO_START, rr)

  # Try to move one character in "direction".  Return 1, -1 or 0, indicating that the selection got bigger, or
  # smaller, or is unchanged.
  moveInDirection: (direction) ->
    length = @selection.toString().length
    @selection.modify "extend", direction, character
    @selection.toString().length - length

  # Get the direction of the selection, either forward or backward.
  # FIXME(smblott).  There has to be a better way!
  # NOTE(smblott).  There is. See here: https://dom.spec.whatwg.org/#interface-range.
  getDirection: ->
    # Try to move the selection forward or backward, then check whether it got bigger or smaller (then restore
    # it).
    for type in [ forward, backward ]
      if success = @moveInDirection type
        @moveInDirection @opposite[type]
        return if 0 < success then type else @opposite[type]

  nextCharacter: (direction) ->
    if @moveInDirection direction
      text = @selection.toString()
      @moveInDirection @opposite[direction]
      text.charAt if @getDirection() == forward then text.length - 1 else 0

  moveByWord: (direction) ->
    @runMovement "#{direction} word" unless /\s/.test @nextCharacter direction
    while /\s/.test @nextCharacter direction
      break unless @selectionChanged =>
        @runMovement "#{direction} character"

  # Run a movement command.
  runMovement: (movement) ->
    length = @selection.toString().length
    @selection.modify @alterMethod, movement.split(" ")...
    @alterMethod == "move" or @selection.toString().length != length

  runMovements: (movements) ->
    console.log movements
    for movement in movements
      break unless @runMovement movement

  movements:
    "l": "forward character"
    "h": "backward character"
    "j": "forward line"
    "k": "backward line"
    "e": "forward word"
    "b": "backward word"
    "B": "backward word"
    ")": "forward sentence"
    "(": "backward sentence"
    "}": "forward paragraph"
    "{": "backward paragraph"
    "$": "forward lineboundary"
    "0": "backward lineboundary"
    "G": "forward documentboundary"
    "g": "backward documentboundary"
    "w": -> @moveByWord forward
    "W": -> @moveByWord forward

    "o": ->
      # Swap the anchor and focus.  This is too slow if the selection is large.
      direction = @getDirection()
      length = @selection.toString().length
      @selection[if direction == forward then "collapseToEnd" else "collapseToStart"]()
      @selection.modify "extend", @opposite[direction], character for [0...length]

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
              @selection = window.getSelection()
              @runCountPrefixTimes =>
                switch typeof @movements[keyChar]
                  when "string"
                    @runMovement @movements[keyChar]
                  when "function"
                    @movements[keyChar].call @
              @scrollIntoView()

  # Adapted from: http://roysharon.com/blog/37.
  # I have no idea how this works (smblott, 2015/1/22).
  getLeadingElement: (selection) ->
    r = t = selection.getRangeAt 0
    if selection.type == "Range"
      r = t.cloneRange()
      r.collapse @getDirection() == backward
    t = r.startContainer
    t = t.childNodes[r.startOffset] if t.nodeType == 1
    o = t
    o = o.previousSibling while o and o.nodeType != 1
    t = o || t?.parentNode
    t

  # Try to scroll the leading end of the selection into view.
  scrollIntoView: ->
    if document.activeElement and DomUtils.isEditable document.activeElement
      element = document.activeElement
      if element.clientHeight < element.scrollHeight
        if element.isContentEditable
          # How do we do this?
        else
          coords = DomUtils.getCaretCoordinates element, element.selectionStart
          Scroller.scrollToPosition element, coords.top, coords.left
    else
      # getLeadingElement() seems to work most, but not all, of the time.
      leadingElement = @getLeadingElement @selection
      Scroller.scrollIntoView leadingElement if leadingElement

class VisualMode extends Movement
  constructor: (options = {}) ->
    @selection = window.getSelection()
    type = @selection.type

    if type == "None"
      HUD.showForDuration "An initial selection is required for visual mode.", 2500
      return

    # Try to start with a visible selection.
    if type == "Caret" # or @selection.isCollapsed (broken if selection is in and input)
      @moveInDirection(forward) or @moveInDirection backward

    defaults =
      name: "visual"
      badge: "V"
      exitOnEscape: true
      alterMethod: "extend"

      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            switch String.fromCharCode event.charCode
              when "y"
                text = window.getSelection().toString()
                chrome.runtime.sendMessage
                  handler: "copyToClipboard"
                  data: text
                @exit()
                length = text.length
                suffix = if length == 1 then "" else "s"
                text = text[...12] + "..." if 15 < length
                text = text.replace /\n/g, " "
                HUD.showForDuration "Yanked #{length} character#{suffix}: \"#{text}\".", 2500

    super extend defaults, options
    @debug = true

    # FIXME(smblott).  We can't handle the selection changing with the mouse while while visual-mode is
    # active.  This "fix" doesn't work.
    # work.
    # onMouseUp = (event) =>
    #   @alwaysContinueBubbling =>
    #     if event.which == 1
    #       window.removeEventListener onMouseUp
    #       new VisualMode @options
    # window.addEventListener "mouseup", onMouseUp, true

  exit: ->
    super()
    unless @options.underEditMode
      if document.activeElement and DomUtils. isEditable document.activeElement
        document.activeElement.blur()

class EditMode extends Movement
  @activeElements = []

  constructor: (options = {}) ->
    defaults =
      name: "edit"
      badge: "E"
      exitOnEscape: true
      alterMethod: "move"

    @debug = true
    @element = document.activeElement
    return unless @element and DomUtils.isEditable @element
    super extend defaults, options
    handlerStack.debug = true

    extend @movements,
      "i": => @enterInsertMode()
      "a": => @enterInsertMode()
      "o": => @openLine forward
      "O": => @openLine backward

  exit: (event, target) ->
    super()
    @element.blur() if target? and DomUtils.isDOMDescendant @element, target
    EditMode.activeElements = EditMode.activeElements.filter (element) => element != @element

  enterInsertMode: ->
    new InsertMode
      badge: "I"
      blurOnEscape: false

  openLine: (direction) ->
    @runMovement "#{direction} lineboundary"
    @enterInsertMode()
    @simulateTextEntry "\n"
    @runMovement "backward character" if direction == backward

  simulateTextEntry: (text) ->
    event = document.createEvent "TextEvent"
    event.initTextEvent "textInput", true, true, null, text
    document.activeElement.dispatchEvent event

root = exports ? window
root.VisualMode = VisualMode
root.EditMode = EditMode

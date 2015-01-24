
# To do:
# - edit-mode losing the focus
# - line-visual mode
# - better implementation of `o`
# - caret mode

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
    handlerId = handlerStack.push
      _name: "#{@id}/suppress-printable"
      keydown: handler
      keypress: handler
      keyup: handler

    super options
    @handlers.push handlerId

# This watches keyboard events and maintains @countPrefix as number keys and other keys are pressed.
class MaintainCount extends SuppressPrintable
  constructor: (options) ->
    @countPrefix = options.initialCount || ""
    super options

    @push
      _name: "#{@id}/maintain-count"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            @countPrefix =
              if keyChar?.length == 1 and "0" <= keyChar <= "9" and @countPrefix + keyChar != "0"
                if @options.initialCount
                  @countPrefix = ""
                  delete @options.initialCount
                @countPrefix + keyChar
              else
                ""

# Some symbolic names.
forward = "forward"
backward = "backward"
character = "character"

# This implements movement commands with count prefixes (using MaintainCount) for both visual mode and edit
# mode.
class Movement extends MaintainCount
  opposite: { forward: backward, backward: forward }

  copy: (text) ->
    chrome.runtime.sendMessage
      handler: "copyToClipboard"
      data: text

  paste: (callback) ->
    chrome.runtime.sendMessage handler: "pasteFromClipboard", (response) ->
      callback response

  # Call a function.  Return true if the selection changed, false otherwise.
  selectionChanged: (func) ->
    r = @selection.getRangeAt(0).cloneRange()
    length = @selection.toString().length
    func()
    rr = @selection.getRangeAt 0
    rr.startContainer != r.startContainer or
      rr. startOffset != r.startOffset or
      @selection.toString().length != length

  # Try to move one character in "direction".  Return 1, -1 or 0, indicating whether the selection got bigger,
  # or smaller, or is unchanged.
  moveInDirection: (direction) ->
    length = @selection.toString().length
    @selection.modify "extend", direction, character
    @selection.toString().length - length

  # Get the direction of the selection.  The selection is "forward" if the focus is at or after the anchor,
  # and "backward" otherwise.
  # NOTE(smblott). Could be better, see: https://dom.spec.whatwg.org/#interface-range.
  getDirection: ->
    # Try to move the selection forward or backward, check whether it got bigger or smaller (then restore it).
    for type in [ forward, backward ]
      if success = @moveInDirection type
        @moveInDirection @opposite[type]
        return if 0 < success then type else @opposite[type]

  moveForwardWord: (direction) ->
    # We use two forward words and one backword so that we end up at the end of the word if we are at the end
    # of the text.  Currently broken if the very-next characters is whitespace.
    movements = [ "forward word", "forward word", "forward character", "backward character", "backward word" ]
    @runMovements movements

  swapFocusAndAnchor: ->
    direction = @getDirection()
    length = @selection.toString().length
    @selection[if direction == forward then "collapseToEnd" else "collapseToStart"]()
    @selection.modify "extend", @opposite[direction], character for [0...length]

  protectClipboard: do ->
    locked = false

    (func) ->
      if @alterMethod == "move" and not locked
        locked = true
        @paste (text) =>
          result = func text
          @copy text
          locked = false
          result
      else
        func()

  # Run a movement command.  Return true if the selection changed, false otherwise.
  runMovement: (movement) ->
    @selectionChanged =>
      movement = movement.split(" ")
      if movement[0] == forward and movement[1] == "lineboundary" and @alterMethod == "extend"
        # Special case.  When we move forward to a line boundary, we're often just moving to the point at
        # which the text wraps, which is of no particular use.  Instead, we keep advancing until we find a
        # newline character.  This trailing newline character is included in the selection.
        atEndOfLine = =>
          if @selectionChanged(=> @selection.modify @alterMethod, "forward", "character")
            text = @selection.toString()
            console.log text[text.length - 1] != "\n", text.length, text
            text[text.length - 1] == "\n"
          else
            true

        @selection.modify @alterMethod, movement...
        @selection.modify @alterMethod, movement... while not atEndOfLine()
      else
        # Normal case.
        @selection.modify @alterMethod, movement...

  # Run a sequence of movements; bail immediately on any failure to change the selection.
  runMovements: (movements) ->
    for movement in movements
      break unless @runMovement movement

  movements:
    "l": "forward character"
    "h": "backward character"
    "j": "forward line"
    "k": "backward line"
    "e": "forward word"
    "b": "backward word"
    "w": -> @moveForwardWord()
    ")": "forward sentence"
    "(": "backward sentence"
    "}": "forward paragraph"
    "{": "backward paragraph"
    "$": "forward lineboundary"
    "0": "backward lineboundary"
    "G": "forward documentboundary"
    "g": "backward documentboundary"
    "Y": -> @selectLine()
    "o": -> @swapFocusAndAnchor()

  constructor: (options) ->
    @selection = window.getSelection()
    @movements = extend {}, @movements
    @commands = {}
    @alterMethod = options.alterMethod || "extend"
    @keyQueue = ""
    @yankedText = ""
    super extend options

    # Aliases.
    @movements.B = @movements.b
    @movements.W = @movements.w

    if @options.runMovement
      @handleMovementKeyChar @options.runMovement
      @yank()
      return

    @push
      _name: "#{@id}/keypress"
      keypress: (event) =>
        unless event.metaKey or event.ctrlKey or event.altKey
          @keyQueue += String.fromCharCode event.charCode
          # We allow at most three characters for a command or movement mapping.
          @keyQueue = @keyQueue.slice Math.max 0, @keyQueue.length - 3
          # Try each possible multi-character keyChar sequence, from longest to shortest.
          for keyChar in (@keyQueue[i..] for i in [0...@keyQueue.length])
            if @movements[keyChar] or @commands[keyChar]
              @keyQueue = ""
              @selection = window.getSelection()

              if @commands[keyChar]
                @commands[keyChar].call @
                @scrollIntoView()
                return @suppressEvent

              else if @movements[keyChar]
                @handleMovementKeyChar keyChar

                if @options.onYank or @options.oneMovementOnly
                  @scrollIntoView()
                  @yank()
                  return @suppressEvent

                break

        @continueBubbling

  handleMovementKeyChar: (keyChar) ->
    # We need to copy the count prefix immediately, because protectClipboard is asynchronous.
    count = if 0 < @countPrefix.length then parseInt @countPrefix else 1
    @countPrefix = ""
    if @movements[keyChar]
      @protectClipboard =>
        for [0...count]
          switch typeof @movements[keyChar]
            when "string" then @runMovement @movements[keyChar]
            when "function" then @movements[keyChar].call @
        @scrollIntoView()

  yank: (args = {}) ->
    @yankedText = window.getSelection().toString()
    @selection.deleteFromDocument() if args.deleteFromDocument or @options.deleteFromDocument
    console.log "yank:", @yankedText

    text = @yankedText.replace /\s+/g, " "
    length = text.length
    text = text[...12] + "..." if 15 < length
    HUD.showForDuration "Yanked #{length} character#{if length == 1 then "" else "s"}: \"#{text}\".", 2500

    @exit()
    @yankedText

  exit: (event) ->
    super()
    unless @options.underEditMode
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement.blur()
    if 0 < @selection.toString().length
      @selection[if @getDirection() == backward then "collapseToEnd" else "collapseToStart"]()
    @options.onYank.call @ if @options.onYank
    # Because the various selection operations can mess with the clipboard, this must be the very-last thing
    # we do.
    @copy @yankedText if @yankedText

  selectLine: ->
    direction = @getDirection()
    for direction in [ @opposite[direction], direction ]
      console.log direction
      @runMovement "#{direction} lineboundary"
      @swapFocusAndAnchor()

  # Adapted from: http://roysharon.com/blog/37.
  # I have no idea how this works (smblott, 2015/1/22).
  # The intention is to find the element containing the focus.  That's the element we need to scroll into
  # view.
  getElementWithFocus: (selection) ->
    r = t = selection.getRangeAt 0
    if selection.type == "Range"
      r = t.cloneRange()
      r.collapse(@getDirection() == backward)
    t = r.startContainer
    t = t.childNodes[r.startOffset] if t.nodeType == 1
    o = t
    o = o.previousSibling while o and o.nodeType != 1
    t = o || t?.parentNode
    t

  # Try to scroll the focus into view.
  scrollIntoView: ->
    @protectClipboard =>
      element = document.activeElement
      if element and DomUtils.isEditable element
        if element.clientHeight < element.scrollHeight
          if element.isContentEditable
            # How do we do this?
          else
            position = if @getDirection() == backward then element.selectionStart else element.selectionEnd
            coords = DomUtils.getCaretCoordinates element, position
            Scroller.scrollToPosition element, coords.top, coords.left
      else
        # getElementWithFocus() seems to work most (but not all) of the time.
        leadingElement = @getElementWithFocus @selection
        Scroller.scrollIntoView leadingElement if leadingElement

class VisualMode extends Movement
  constructor: (options = {}) ->
    @selection = window.getSelection()
    switch @selection.type
      when "None"
        HUD.showForDuration "Create a selection before entering visual mode.", 2500
        return
      when "Caret"
        # Try to start with a visible selection.
        @moveInDirection(forward) or @moveInDirection backward unless options.underEditMode

    defaults =
      name: "visual"
      badge: "V"
      exitOnEscape: true
      alterMethod: "extend"
      underEditMode: false
    super extend defaults, options

    extend @commands,
      "y": ->
        # Special case: "yy" (the first from edit mode, and now the second).
        @selectLine() if @options.expectImmediateY and @keyQueue == ""
        @yank()

    if @options.underEditMode
      extend @commands,
        "d": @yank
        "c": -> @yank(); enterInsertMode()

class VisualModeForEdit extends VisualMode
  constructor: (options = {}) ->
    super extend options, underEditMode: true

class EditMode extends Movement
  constructor: (options = {}) ->
    @element = document.activeElement
    return unless @element and DomUtils.isEditable @element

    super
      name: "edit"
      badge: "E"
      exitOnEscape: true
      alterMethod: "move"

    extend @commands,
      "i": enterInsertMode
      "a": enterInsertMode
      "A": => @runMovement "forward lineboundary"; enterInsertMode()
      "o": => @openLine forward
      "O": => @openLine backward
      "p": => @pasteClipboard forward
      "P": => @pasteClipboard backward
      "v": -> new VisualModeForEdit

      "Y": -> @runInVisualMode runMovement: "Y"
      "y": => @runInVisualMode expectImmediateY: true
      "d": => @runInVisualMode deleteFromDocument: true
      "c": => @runInVisualMode
        deleteFromDocument: true
        onYank: -> new InsertMode { badge: "I", blurOnEscape: false }

      "D": => @runInVisualMode runMovement: "$", deleteFromDocument: true
      "C": => @runInVisualMode runMovement: "$", deleteFromDocument: true, onYank: enterInsertMode

    # # Aliases.
    # @commands.Y = @commands.yy

  runInVisualMode: (options = {}) ->
    defaults =
      initialCount: @countPrefix
      oneMovementOnly: true
    new VisualModeForEdit extend defaults, options
    @countPrefix = ""

  pasteClipboard: (direction) ->
    @protectClipboard (text) =>
      if text
        # We use the heuristic that the paste is line oriented if the last character is a newline.  This is
        # consistent with the way runMovement selects text in visual mode for "forward lineboundary".
        lineOriented = /\n$/.test text
        if lineOriented
          @runMovement "#{direction} lineboundary"
          @runMovement "#{direction} character" if direction == forward
        DomUtils.simulateTextEntry @element, text
        # Slow!  Expensive!  Better way?
        @runMovement "backward character" for [0...text.length] if lineOriented

  openLine: (direction) ->
    @runMovement "#{direction} lineboundary"
    enterInsertMode()
    DomUtils.simulateTextEntry @element, "\n"
    @runMovement "backward character" if direction == backward

  exit: (event, target) ->
    super()
    if event?.type = "keydown" and KeyboardUtils.isEscape event
      if target? and DomUtils.isDOMDescendant @element, target
        @element.blur()

enterInsertMode = ->
  new InsertMode { badge: "I", blurOnEscape: false }

root = exports ? window
root.VisualMode = VisualMode
root.EditMode = EditMode

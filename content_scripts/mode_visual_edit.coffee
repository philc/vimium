
# To do:
# - better implementation of `o`
# - caret mode
# - find operations (needs better implementation?)

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

  # Run a movement command.
  runMovement: (movement) ->
    @selection.modify @alterMethod, movement.split(" ")...

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
    for direction in [ forward, backward ]
      if success = @moveInDirection direction
        @moveInDirection @opposite[direction]
        return if 0 < success then direction else @opposite[direction]
    forward

  # An approximation of the vim "w" movement.
  moveForwardWord: (direction) ->
    # This is broken:
    # - On the very last word in the text.
    # - When the next character is not a word character.
    # However, it works well for the common cases, and the additional complexity of fixing these broken cases
    # is probably unwarranted right now (smblott, 2015/1/25).
    movements = [ "forward word", "forward word", "backward word" ]
    @runMovement movement for movement in movements

  # Swap the focus and anchor.
  # FIXME(smblott). This implementation is rediculously inefficient if the selection is large.
  reverseSelection: ->
    direction = @getDirection()
    length = @selection.toString().length
    @selection[if direction == forward then "collapseToEnd" else "collapseToStart"]()
    @selection.modify "extend", @opposite[direction], character for [0...length]

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
    "w": -> @moveForwardWord()
    "Y": -> @selectLine()
    "o": -> @reverseSelection()

  constructor: (options) ->
    @selection = window.getSelection()
    @movements = extend {}, @movements
    @commands = {}
    @alterMethod = options.alterMethod || "extend"
    @keyQueue = ""
    @yankedText = ""
    super options

    # Aliases.
    @movements.B = @movements.b
    @movements.W = @movements.w

    if @options.runMovement
      # This instance has been created just to run a single movement.
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
          # Try each possible multi-character keyChar sequence, from longest to shortest (e.g. with "abc", we
          # try "abc", "bc" and "c").
          for command in (@keyQueue[i..] for i in [0...@keyQueue.length])
            if @movements[command] or @commands[command]
              @selection = window.getSelection()
              @keyQueue = ""

              if @commands[command]
                @commands[command].call @
                @scrollIntoView()
                return @suppressEvent

              else if @movements[command]
                @handleMovementKeyChar command

                if @options.oneMovementOnly
                  @yank()
                  return @suppressEvent

                break

        @continueBubbling

  handleMovementKeyChar: (keyChar) ->
    # We grab the count prefix immediately, because protectClipboard may be asynchronous (edit mode), and
    # @countPrefix may be reset if we wait.
    count = if 0 < @countPrefix.length then parseInt @countPrefix else 1
    @countPrefix = ""
    if @movements[keyChar]
      @protectClipboard =>
        for [0...count]
          switch typeof @movements[keyChar]
            when "string" then @runMovement @movements[keyChar]
            when "function" then @movements[keyChar].call @
        @scrollIntoView()

  # Yank the selection.  Always exits.  Returns the yanked text.
  yank: (args = {}) ->
    @yankedText = @selection.toString()
    @selection.deleteFromDocument() if args.deleteFromDocument or @options.deleteFromDocument
    console.log "yank:", @yankedText

    message = @yankedText.replace /\s+/g, " "
    length = message.length
    message = message[...12] + "..." if 15 < length
    plural = if length == 1 then "" else "s"
    HUD.showForDuration "Yanked #{length} character#{plural}: \"#{message}\".", 2500

    @options.onYank.call @ @yankedText if @options.onYank
    @exit()
    @yankedText

  exit: (event, target) ->
    super event, target
    unless @options.underEditMode
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement.blur()
    unless event?.type == "keydown" and KeyboardUtils.isEscape event
      if 0 < @selection.toString().length
        @selection[if @getDirection() == backward then "collapseToEnd" else "collapseToStart"]()
    @copy @yankedText if @yankedText

  selectLine: ->
    for direction in [ backward, forward ]
      @reverseSelection()
      @runMovement "#{direction} lineboundary"

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
        elementWithFocus = @getElementWithFocus @selection
        Scroller.scrollIntoView elementWithFocus if elementWithFocus

  # Adapted from: http://roysharon.com/blog/37.
  # I have no idea how this works (smblott, 2015/1/22).
  # The intention is to find the element containing the focus.  That's the element we need to scroll into
  # view. It seems to work most (but not all) of the time.
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
    super extend defaults, options

    extend @commands,
      "y": ->
        # Special case: "yy" (the first from edit mode, and now the second).
        @selectLine() if @options.expectImmediateY and @keyQueue == ""
        @yank()

    if @options.underEditMode
      extend @commands,
        "d": -> @yank deleteFromDocument: true
        "c": -> @yank(); enterInsertMode()

    # Map "n" and "N" for poor-man's find.
    unless @options.underEditMode
      do =>
        findBackwards = false
        query = getFindModeQuery()
        return unless query

        executeFind = => @protectClipboard =>
          initialRange = @selection.getRangeAt(0).cloneRange()
          caseSensitive = /[A-Z]/.test query
          if query
            window.find query, caseSensitive, findBackwards, true, false, true, false
            newRange = @selection.getRangeAt(0).cloneRange()
            range = document.createRange()
            range.setStart initialRange.startContainer, initialRange.startOffset
            range.setEnd newRange.endContainer, newRange.endOffset
            @selection.removeAllRanges()
            @selection.addRange range

        extend @movements,
          "n": -> executeFind()
          "N": -> findBackwards = not findBackwards; executeFind()

    @clipboardContents = ""
    @paste (text) => @clipboardContents = text

  protectClipboard: (func) ->
    func()
    @copy @clipboardContents

  copy: (text) ->
    super @clipboardContents = text

class VisualLineMode extends VisualMode
  constructor: (options = {}) ->
    super options
    @selectLine()

  handleMovementKeyChar: (keyChar) ->
    super keyChar
    @runMovement "#{@getDirection()} lineboundary", true

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
      "v": -> new VisualMode underEditMode: true

      "Y": -> @enterVisualMode runMovement: "Y"
      "y": => @enterVisualMode expectImmediateY: true
      "d": => @enterVisualMode deleteFromDocument: true
      "c": => @enterVisualMode
        deleteFromDocument: true
        onYank: -> new InsertMode { badge: "I", blurOnEscape: false }

      "D": => @enterVisualMode runMovement: "$", deleteFromDocument: true
      "C": => @enterVisualMode runMovement: "$", deleteFromDocument: true, onYank: enterInsertMode

  enterVisualMode: (options = {}) ->
    defaults =
      underEditMode: true
      initialCount: @countPrefix
      oneMovementOnly: true
    new VisualMode extend defaults, options
    @countPrefix = ""

  pasteClipboard: (direction) ->
    @paste (text) =>
      DomUtils.simulateTextEntry @element, text if text

  openLine: (direction) ->
    @runMovement "#{direction} lineboundary"
    enterInsertMode()
    DomUtils.simulateTextEntry @element, "\n"
    @runMovement "backward character" if direction == backward

  exit: (event, target) ->
    super()
    if event?.type == "keydown" and KeyboardUtils.isEscape event
      if target? and DomUtils.isDOMDescendant @element, target
        @element.blur()

  # Backup the clipboard, then call a function (which may affect the selection text, and hence the
  # clipboard too), then restore the clipboard.
  protectClipboard: do ->
    locked = false
    clipboard = ""

    (func) ->
      if locked
        func()
      else
        locked = true
        @paste (text) =>
          clipboard = text
          func()
          @copy clipboard
          locked = false

enterInsertMode = ->
  new InsertMode { badge: "I", blurOnEscape: false }

root = exports ? window
root.VisualMode = VisualMode
root.VisualLineMode = VisualLineMode
root.EditMode = EditMode

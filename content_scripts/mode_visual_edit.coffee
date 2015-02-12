
#
# The main modes defined here are:
# - VisualMode
# - VisualLineMode
# - CaretMode
# - EditMode (experimental)
#
# SuppressPrintable and CountPrefix are shared utility base classes.
# Movement is a shared vim-like movement base class.
#
# The class inheritance hierarchy is:
# - Mode, SuppressPrintable, CountPrefix, Movement, [ VisualMode | CaretMode | EditMode ]
# - Mode, SuppressPrintable, CountPrefix, Movement, VisualMode, VisualLineMode
#
# The possible mode states are:
# - ..., VisualMode
# - ..., VisualLineMode
# - ..., CaretMode
# - ..., VisualMode, FindMode
# - ..., VisualLineMode, FindMode
# - ..., CaretMode, FindMode
# - ..., EditMode
# - ..., EditMode, InsertMode
# - ..., EditMode, VisualMode
# - ..., EditMode, VisualLineMode
#

# This prevents printable characters from being passed through to underlying modes or the underlying page.
class SuppressPrintable extends Mode
  constructor: (options = {}) ->
    handler = (event) =>
      return @stopBubblingAndTrue if not KeyboardUtils.isPrintable event
      return @suppressEvent if event.type != "keydown"
      # Completely suppress Backspace and Delete, they change the selection.
      return @suppressEvent if event.keyCode in [ keyCodes.backspace, keyCodes.deleteKey ]
      # Suppress propagation (but not preventDefault) for keydown, printable events.
      DomUtils.suppressPropagation event
      @stopBubblingAndFalse

    super extend options, keydown: handler, keypress: handler, keyup: handler

# This monitors keypresses and maintains the count prefix.
class CountPrefix extends SuppressPrintable
  constructor: (options) ->
    @countPrefix = ""
    # This is an initial multiplier for the first count.  It allows edit mode to implement both "d3w" and
    # "3dw". Also, "3d2w" deletes six words.
    @countPrefixFactor = options.initialCountPrefix || 1
    super options

    @push
      _name: "#{@id}/count-prefix"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            @countPrefix =
              if keyChar.length == 1 and "0" <= keyChar <= "9" and @countPrefix + keyChar != "0"
                @countPrefix + keyChar
              else
                ""

  getCountPrefix: ->
    count = @countPrefixFactor * (if 0 < @countPrefix.length then parseInt @countPrefix else 1)
    @countPrefix = ""; @countPrefixFactor = 1
    count

# Symbolic names for some common strings.
forward = "forward"
backward = "backward"
character = "character"
word = "word"
line = "line"
sentence = "sentence"
paragraph = "paragraph"
vimword = "vimword"
lineboundary= "lineboundary"

# This implements vim-like movements, and includes quite a number of gereral utility methods.
class Movement extends CountPrefix
  opposite: forward: backward, backward: forward

  # Paste from clipboard.
  paste: (callback) ->
    chrome.runtime.sendMessage handler: "pasteFromClipboard", (response) -> callback response

  # Copy to clipboard.
  copy: (text, isFinalUserCopy = false) ->
    chrome.runtime.sendMessage handler: "copyToClipboard", data: text
    # If isFinalUserCopy is set, then we're copying the final text selected by the user (and exiting).
    # However, @protectClipboard may later try to restore the original clipboard contents.  Therefore, we
    # disable copy so that subsequent copies do not propagate.
    @copy = (->) if isFinalUserCopy

  # This s used whenever manipulating the selection may, as a side effect, change the clipboard's contents.
  # We restore the original clipboard contents when we're done. May be asynchronous.  We use a lock so that
  # calls can be nested.  We do this primarily for edit mode, where the user does not expect caret movements
  # to change the clipboard contents.
  protectClipboard: do ->
    locked = false

    (func) ->
      if locked then func()
      else
        locked = true
        @paste (text) =>
          func(); @copy text; locked = false

  # Replace the current mode with another. For example, replace caret mode with visual mode, or replace visual
  # mode with visual-line mode.
  changeMode: (mode, options = {}) ->
    @exit()
    if @options.parentMode
      @options.parentMode.launchSubMode mode, options
    else
      new mode options

  # Return the character following (to the right of) the focus, and leave the selection unchanged.  Returns
  # undefined if no such character exists.
  getNextForwardCharacter: ->
    beforeText = @selection.toString()
    if beforeText.length == 0 or @getDirection() == forward
      @selection.modify "extend", forward, character
      afterText = @selection.toString()
      if beforeText != afterText
        @selection.modify "extend", backward, character
        afterText[afterText.length - 1]
    else
      beforeText[0] # Existing range selection is backwards.

  # As above, but backwards.
  getNextBackwardCharacter: ->
    beforeText = @selection.toString()
    if beforeText.length == 0 or @getDirection() == backward
      @selection.modify "extend", backward, character
      afterText = @selection.toString()
      if beforeText != afterText
        @selection.modify "extend", forward, character
        afterText[0]
    else
      beforeText[beforeText.length - 1] # Existing range selection is forwards.

  # Test whether the character following the focus is a word character (and leave the selection unchanged).
  nextCharacterIsWordCharacter: do ->
    regexp = /[A-Za-z0-9_]/; -> regexp.test @getNextForwardCharacter()

  # Run a movement.  This is the core movement method, all movements happen here.  For convenience, the
  # following three argument forms are supported:
  #   @runMovement "forward word"
  #   @runMovement [ "forward", "word" ]
  #   @runMovement "forward", "word"
  #
  # The granularities are word, "character", "line", "lineboundary", "sentence" and "paragraph".  In addition,
  # we implement the pseudo granularity "vimword", which implements vim-like word movement (for "w").
  #
  runMovement: (args...) ->
    # Normalize the various argument forms.
    [ direction, granularity ] =
      if typeof(args[0]) == "string" and args.length == 1
        args[0].trim().split /\s+/
      else
        if args.length == 1 then args[0] else args[...2]

    # Native word movements behave differently on Linux and Windows, see #1441.  So we implement some of them
    # character-by-character.
    if granularity == vimword and direction == forward
      while @nextCharacterIsWordCharacter()
        return unless @runMovements [ forward, character ]
      while @getNextForwardCharacter() and not @nextCharacterIsWordCharacter()
        return unless @runMovements [ forward, character ]

    else if granularity == vimword
      @selection.modify @alterMethod, backward, word

    # As above, we implement this character-by-character to get consistent behavior on Windows and Linux.
    if granularity == word and direction == forward
      while @getNextForwardCharacter() and not @nextCharacterIsWordCharacter()
        return unless @runMovements [ forward, character ]
      while @nextCharacterIsWordCharacter()
        return unless @runMovements [ forward, character ]

    else
      @selection.modify @alterMethod, direction, granularity

  # Return a simple camparable value which depends on various aspects of the selection.  This is used to
  # detect, after a movement, whether the selection has changed.
  hashSelection: (debug) ->
    range = @selection.getRangeAt(0)
    [ @element?.selectionStart, @selection.toString().length, range.anchorOffset, range.focusOffset,
      @selection.extentOffset, @selection.baseOffset ].join "/"

  # Call a function; return true if the selection changed, false otherwise.
  selectionChanged: (func) ->
    before = @hashSelection(); func(); @hashSelection() != before

  # Run a sequence of movements, stopping if a movement fails to change the selection.
  runMovements: (movements...) ->
    for movement in movements
      return false unless @selectionChanged => @runMovement movement
    true

  # Swap the anchor node/offset and the focus node/offset.  This allows us to work with both ends of the
  # selection, and implements "o" for visual mode.
  reverseSelection: ->
    direction = @getDirection()
    element = document.activeElement
    if element and DomUtils.isEditable(element) and not element.isContentEditable
      # Note(smblott). This implementation is unacceptably expensive if the selection is large.  We only use
      # it here because the normal method (below) does not work for simple text inputs.
      length = @selection.toString().length
      @collapseSelectionToFocus()
      @runMovement @opposite[direction], character for [0...length]
    else
      # Normal method (efficient).
      original = @selection.getRangeAt(0).cloneRange()
      range = original.cloneRange()
      range.collapse direction == backward
      @setSelectionRange range
      which = if direction == forward then "start" else "end"
      @selection.extend original["#{which}Container"], original["#{which}Offset"]

  # Try to extend the selection one character in direction.  Return positive, negative or 0, indicating
  # whether the selection got bigger, or smaller, or is unchanged.
  extendByOneCharacter: (direction) ->
    length = @selection.toString().length
    @selection.modify "extend", direction, character
    @selection.toString().length - length

  # Get the direction of the selection.  The selection is "forward" if the focus is at or after the anchor,
  # and "backward" otherwise.
  # NOTE(smblott). This could be better, see: https://dom.spec.whatwg.org/#interface-range (however, that
  # probably wouldn't work for text inputs).
  getDirection: ->
    # Try to move the selection forward or backward, check whether it got bigger or smaller (then restore it).
    for direction in [ forward, backward ]
      if change = @extendByOneCharacter direction
        @extendByOneCharacter @opposite[direction]
        return if 0 < change then direction else @opposite[direction]
    forward

  collapseSelectionToAnchor: ->
    if 0 < @selection.toString().length
      @selection[if @getDirection() == backward then "collapseToEnd" else "collapseToStart"]()

  collapseSelectionToFocus: ->
    if 0 < @selection.toString().length
      @selection[if @getDirection() == forward then "collapseToEnd" else "collapseToStart"]()

  setSelectionRange: (range) ->
    @selection.removeAllRanges()
    @selection.addRange range

  # A movement can be either a string (which will be passed to @runMovement count times), or a function (which
  # will be called once with count as its argument).
  movements:
    "l": "forward character"
    "h": "backward character"
    "j": "forward line"
    "k": "backward line"
    "e": "forward word"
    "b": "backward word"
    "w": "forward vimword"
    ")": "forward sentence"
    "(": "backward sentence"
    "}": "forward paragraph"
    "{": "backward paragraph"
    "0": "backward lineboundary"
    "$": "forward lineboundary"
    "G": "forward documentboundary"
    "gg": "backward documentboundary"
    "Y": (count) -> @selectLine count; @yank()

  # This handles a movement, but protects to selection while doing so.
  runMovementKeyChar: (args...) ->
    @protectClipboard => @handleMovementKeyChar args...

  # Handle a single movement keyChar.  This is extended (wrapped) by super-classes.
  handleMovementKeyChar: (keyChar, count = 1) ->
    switch typeof @movements[keyChar]
      when "string" then @runMovement @movements[keyChar] for [0...count]
      when "function" then @movements[keyChar].call @, count
    @scrollIntoView()

  # The bahavior of Movement can be tweaked by setting the following options:
  #   - options.parentMode (a mode)
  #     This instance is a sub-mode of another mode (currently, only edit mode).
  #   - options.oneMovementOnly (truthy/falsy)
  #     This instance is created for one movement only, after which it yanks and exits.
  #   - options.immediateMovement (a keyChar string)
  #     This instance is created for one movement only, and this options specifies the movement (e.g. "j").
  #   - options.deleteFromDocument (truthy/falsy)
  #     When yanking text, also delete it from the document.
  #   - options.onYank (a function)
  #     When yanking text, also call this function, passing the yanked text as an argument.
  #   - options.noCopyToClipboard (truthy/falsy)
  #     If truthy, then do not copy the yanked text to the clipboard when yanking.
  #
  constructor: (options) ->
    @selection = window.getSelection()
    @movements = extend {}, @movements
    @commands = {}
    @keyQueue = ""
    super options

    # Aliases.
    @movements.B = @movements.b
    @movements.W = @movements.w

    if @options.immediateMovement
      # This instance has been created to execute a single, given movement.
      @runMovementKeyChar @options.immediateMovement, @getCountPrefix()
      return

    # This is the main keyboard-event handler for movements and commands for all user modes (visual,
    # visual-line, caret and edit).
    @push
      _name: "#{@id}/keypress"
      keypress: (event) =>
        unless event.metaKey or event.ctrlKey or event.altKey
          @keyQueue += String.fromCharCode event.charCode
          # Keep at most two keyChars in the queue.
          @keyQueue = @keyQueue.slice Math.max 0, @keyQueue.length - 2
          for command in [ @keyQueue, @keyQueue[1..] ]
            if command and (@movements[command] or @commands[command])
              @selection = window.getSelection()
              @keyQueue = ""

              # We need to treat "0" specially.  It can be either a movement, or a continutation of a count
              # prefix.  Don't treat it as a movement if we already have an initial count prefix.
              return @continueBubbling if command == "0" and 0 < @countPrefix.length

              if @commands[command]
                @commands[command].call @, @getCountPrefix()
                @scrollIntoView()
                return @suppressEvent

              else if @movements[command]
                @runMovementKeyChar command, @getCountPrefix()
                return @suppressEvent

        @continueBubbling

    # Install basic bindings for find mode, "n" and "N".  We do not install these bindings if this is a
    # sub-mode of edit mode (because we cannot guarantee that the selection will remain within the active
    # element), or if this instance has been created to execute only a single movement.
    unless @options.parentMode or options.oneMovementOnly
      do =>
        executeFind = (count, findBackwards) =>
          if query = getFindModeQuery findBackwards
            initialRange = @selection.getRangeAt(0).cloneRange()
            for [0...count]
              unless window.find query, Utils.hasUpperCase(query), findBackwards, true, false, true, false
                @setSelectionRange initialRange
                HUD.showForDuration("No matches for '" + query + "'", 1000)
                return
            # The find was successfull. If we're in caret mode, then we should now have a selection, so we can
            # drop back into visual mode.
            @changeMode VisualMode if @name == "caret" and 0 < @selection.toString().length

        @movements.n = (count) -> executeFind count, false
        @movements.N = (count) -> executeFind count, true
        @movements["/"] = ->
          @findMode = window.enterFindMode()
          @findMode.onExit => @changeMode VisualMode
    #
    # End of Movement constructor.

  # Yank the selection; always exits; either deletes the selection or removes it; set @yankedText and return
  # it.
  yank: (args = {}) ->
    @yankedText = @selection.toString()
    @selection.deleteFromDocument() if @options.deleteFromDocument or args.deleteFromDocument
    @selection.removeAllRanges() unless @options.parentMode

    message = @yankedText.replace /\s+/g, " "
    message = message[...12] + "..." if 15 < @yankedText.length
    plural = if @yankedText.length == 1 then "" else "s"
    HUD.showForDuration "Yanked #{@yankedText.length} character#{plural}: \"#{message}\".", 2500

    @options.onYank?.call @, @yankedText
    @exit()
    @yankedText

  exit: (event, target) ->
    unless @options.parentMode or @options.oneMovementOnly
      @selection.removeAllRanges() if event?.type == "keydown" and KeyboardUtils.isEscape event

      # Disabled, pending discussion of fine-tuning the UX.  Simpler alternative is implemented above.
      # # If we're exiting on escape and there is a range selection, then we leave it in place.  However, an
      # # immediately-following Escape clears the selection.  See #1441.
      # if @selection.type == "Range" and event?.type == "keydown" and KeyboardUtils.isEscape event
      #   handlerStack.push
      #     _name: "visual/range/escape"
      #     click: -> handlerStack.remove(); @continueBubbling
      #     focus: -> handlerStack.remove(); @continueBubbling
      #     keydown: (event) =>
      #       handlerStack.remove()
      #       if @selection.type == "Range" and event.type == "keydown" and KeyboardUtils.isEscape event
      #         @collapseSelectionToFocus()
      #         DomUtils.suppressKeyupAfterEscape handlerStack
      #         @suppressEvent
      #       else
      #         @continueBubbling

    super event, target

  # For "daw", "das", and so on.  We select a lexical entity (a word, a sentence or a paragraph).
  # Note(smblott).  It would be better if the entities could be handled symmetrically.  Unfortunately, they
  # cannot, and we have to handle each case individually.
  selectLexicalEntity: (entity, count = 1) ->

    switch entity
      when word
        if @nextCharacterIsWordCharacter()
          @runMovements [ forward, character ], [ backward, word ]
          @collapseSelectionToFocus()
        @runMovements ([0...count].map -> [ forward, vimword ])...

      when sentence
        @runMovements [ forward, character ], [ backward, sentence ]
        @collapseSelectionToFocus()
        @runMovements ([0...count].map -> [ forward, sentence ])...

      when paragraph
        # Chrome's paragraph movements are weird: they're not symmetrical, and tend to stop in odd places
        # (like mid-paragraph, for example).  Here, we define a paragraph as a new-line delimited entity,
        # including the terminating newline.
        # Note(smblott).  This does not currently use the count.
        char = @getNextBackwardCharacter()
        while char? and char != "\n"
          return unless @runMovements [ backward, character ], [ backward, lineboundary ]
          char = @getNextBackwardCharacter()
        @collapseSelectionToFocus()
        char = @getNextForwardCharacter()
        while char? and char != "\n"
          return unless @runMovements [ forward, character ], [ forward, lineboundary ]
          char = @getNextForwardCharacter()
        @runMovement forward, character

  # Scroll the focus into view.
  scrollIntoView: ->
    @protectClipboard =>
      if @element and DomUtils.isEditable @element
        if @element.clientHeight < @element.scrollHeight
          if @element.isContentEditable
            # WIP (edit mode only)...
            elementWithFocus = DomUtils.getElementWithFocus @selection, @getDirection() == backward
            # position = @element.getClientRects()[0].top - elementWithFocus.getClientRects()[0].top
            # console.log "top", position
            # Scroller.scrollToPosition @element, position, 0
            position = elementWithFocus.getClientRects()[0].bottom - @element.getClientRects()[0].top - @element.clientHeight + @element.scrollTop
            Scroller.scrollToPosition @element, position, 0
          else
            position = if @getDirection() == backward then @element.selectionStart else @element.selectionEnd
            coords = DomUtils.getCaretCoordinates @element, position
            Scroller.scrollToPosition @element, coords.top, coords.left
      else
        unless @selection.type == "None"
          elementWithFocus = DomUtils.getElementWithFocus @selection, @getDirection() == backward
          Scroller.scrollIntoView elementWithFocus if elementWithFocus

class VisualMode extends Movement
  constructor: (options = {}) ->
    @alterMethod = "extend"

    defaults =
      name: "visual"
      badge: "V"
      singleton: VisualMode
      exitOnEscape: true
    super extend defaults, options

    # Establish or use the initial selection.  If that's not possible, then enter caret mode.
    unless @options.oneMovementOnly or options.immediateMovement
      if @options.parentMode and @selection.type == "Caret"
        # We're being called from edit mode, so establish an intial visible selection.
        @extendByOneCharacter(forward) or @extendByOneCharacter backward
      else
        if @selection.type in [ "Caret", "Range" ]
          elementWithFocus = DomUtils.getElementWithFocus @selection, @getDirection() == backward
          if DomUtils.getVisibleClientRect elementWithFocus
            if @selection.type == "Caret"
              # The caret is in the viewport. Make make it visible.
              @extendByOneCharacter(forward) or @extendByOneCharacter backward
          else
            # The selection is outside of the viewport: clear it.  We guess that the user has moved on, and is
            # more likely to be interested in visible content.
            @selection.removeAllRanges()

        if @selection.type != "Range"
          HUD.showForDuration "No usable selection, entering caret mode...", 2500
          @changeMode CaretMode
          return

    @push
      _name: "#{@id}/enter/click"
      # Yank on <Enter>.
      keypress: (event) =>
        if event.keyCode == keyCodes.enter
          unless event.metaKey or event.ctrlKey or event.altKey or event.shiftKey
            @yank()
            return @suppressEvent
        @continueBubbling
      # Click in a focusable element exits.
      click: (event) =>
        @alwaysContinueBubbling =>
          unless @options.parentMode
            @exit event, event.target if DomUtils.isFocusable event.target

    # Visual-mode commands.
    unless @options.oneMovementOnly
      @commands.y = -> @yank()
      @commands.p = -> chrome.runtime.sendMessage handler: "openUrlInCurrentTab", url: @yank()
      @commands.P = -> chrome.runtime.sendMessage handler: "openUrlInNewTab", url: @yank()
      @commands.V = -> @changeMode VisualLineMode
      @commands.c = -> @collapseSelectionToFocus(); @changeMode CaretMode
      @commands.o = -> @reverseSelection()

      # Additional commands when run under edit mode.
      if @options.parentMode
          @commands.x = -> @yank deleteFromDocument: true
          @commands.d = -> @yank deleteFromDocument: true
          @commands.c = -> @yank deleteFromDocument: true; @options.parentMode.enterInsertMode()

    # For edit mode's "yy" and "dd".
    if @options.yankLineCharacter
      @commands[@options.yankLineCharacter] = (count) ->
        @selectLine count; @yank()

    # For edit mode's "daw", "cas", and so on.
    if @options.oneMovementOnly
      @commands.a = (count) ->
        for entity in [ word, sentence, paragraph ]
          do (entity) =>
            @commands[entity.charAt 0] = ->
              @selectLexicalEntity entity, count; @yank()
    #
    # End of VisualMode constructor.

  exit: (event, target) ->
    unless @options.parentMode
      # Don't leave the user in insert mode just because they happen to have selected text within an input
      # element.
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement.blur() unless event?.type == "click"

    super event, target
    if @yankedText?
      unless @options.noCopyToClipboard
        console.log "yank:", @yankedText if @debug
        @copy @yankedText, true

  # Call sub-class; then yank, if we've only been created for a single movement.
  handleMovementKeyChar: (args...) ->
    super args...
    @yank() if @options.oneMovementOnly or @options.immediateMovement

  selectLine: (count) ->
    @reverseSelection() if @getDirection() == forward
    @runMovement backward, lineboundary
    @reverseSelection()
    @runMovement forward, line for [1...count]
    @runMovement forward, lineboundary
    # Include the next character if it is a newline.
    @runMovement forward, character if @getNextForwardCharacter() == "\n"

class VisualLineMode extends VisualMode
  constructor: (options = {}) ->
    super extend { name: "visual/line" }, options
    @extendSelection()
    @commands.v = -> @changeMode VisualMode

  handleMovementKeyChar: (args...) ->
    super args...
    @extendSelection()

  extendSelection: ->
    initialDirection = @getDirection()
    for direction in [ initialDirection, @opposite[initialDirection] ]
      @runMovement direction, lineboundary
      @reverseSelection()

class CaretMode extends Movement
  constructor: (options = {}) ->
    @alterMethod = "move"

    defaults =
      name: "caret"
      badge: "C"
      singleton: VisualMode
      exitOnEscape: true
    super extend defaults, options

    # Establish the initial caret.
    switch @selection.type
      when "None"
        @establishInitialSelectionAnchor()
        if @selection.type == "None"
          HUD.showForDuration "Create a selection before entering visual mode.", 2500
          @exit()
          return
      when "Range"
        @collapseSelectionToAnchor()

    @selection.modify "extend", forward, character
    @scrollIntoView()

    @push
      _name: "#{@id}/click"
      # Click in a focusable element exits.
      click: (event) =>
        @alwaysContinueBubbling =>
          @exit event, event.target if DomUtils.isFocusable event.target

    # Commands to exit caret mode, and enter visual mode.
    extend @commands,
      v: -> @changeMode VisualMode
      V: -> @changeMode VisualLineMode

  handleMovementKeyChar: (args...) ->
    @collapseSelectionToAnchor()
    super args...
    @selection.modify "extend", forward, character

  # When visual mode starts and there's no existing selection, we launch CaretMode and try to establish a
  # selection.  As a heuristic, we pick the first non-whitespace character of the first visible text node
  # which seems to be big enough to be interesting.
  # TODO(smblott).  It might be better to do something similar to Clearly or Readability; that is, try to find
  # the start of the page's main textual content.
  establishInitialSelectionAnchor: ->
    nodes = document.createTreeWalker document.body, NodeFilter.SHOW_TEXT
    while node = nodes.nextNode()
      # Don't choose short text nodes; they're likely to be part of a banner.
      if node.nodeType == 3 and 50 <= node.data.trim().length
        element = node.parentElement
        if DomUtils.getVisibleClientRect(element) and not DomUtils.isEditable element
          # Start at the offset of the first non-whitespace character.
          offset = node.data.length - node.data.replace(/^\s+/, "").length
          range = document.createRange()
          range.setStart node, offset
          range.setEnd node, offset
          @setSelectionRange range
          return true
    false

class EditMode extends Movement
  constructor: (options = {}) ->
    @alterMethod = "move"
    @element = document.activeElement
    return unless @element and DomUtils.isEditable @element

    defaults =
      name: "edit"
      badge: "E"
      exitOnEscape: true
      exitOnBlur: @element
    super extend defaults, options

    # Edit mode commands.
    extend @commands,
      i: -> @enterInsertMode()
      a: -> @enterInsertMode()
      I: -> @runMovement backward, lineboundary; @enterInsertMode()
      A: -> @runMovement forward, lineboundary; @enterInsertMode()
      o: -> @openLine forward
      O: -> @openLine backward
      p: -> @pasteClipboard forward
      P: -> @pasteClipboard backward
      v: -> @launchSubMode VisualMode
      V: -> @launchSubMode VisualLineMode

      Y: (count) -> @enterVisualModeForMovement count, immediateMovement: "Y"
      x: (count) -> @enterVisualModeForMovement count, immediateMovement: "l", deleteFromDocument: true, noCopyToClipboard: true
      X: (count) -> @enterVisualModeForMovement count, immediateMovement: "h", deleteFromDocument: true, noCopyToClipboard: true
      y: (count) -> @enterVisualModeForMovement count, yankLineCharacter: "y"
      d: (count) -> @enterVisualModeForMovement count, yankLineCharacter: "d", deleteFromDocument: true
      c: (count) -> @enterVisualModeForMovement count, deleteFromDocument: true, onYank: => @enterInsertMode()

      D: (count) -> @enterVisualModeForMovement 1, immediateMovement: "$", deleteFromDocument: true
      C: (count) -> @enterVisualModeForMovement 1, immediateMovement: "$", deleteFromDocument: true, onYank: => @enterInsertMode()

      '~': (count) -> @swapCase count, true
      'g~': (count) -> @swapCase count, false

      # Disabled.  Doesn't work reliably.
      # J: (count) ->
      #   for [0...count]
      #     @runMovement forward, lineboundary
      #     @enterVisualModeForMovement 1, immediateMovement: "w", deleteFromDocument: true, noCopyToClipboard: true
      #     DomUtils.simulateTextEntry @element, " "

      r: (count) ->
        handlerStack.push
          _name: "repeat-character"
          keydown: (event) => DomUtils.suppressPropagation event; @stopBubblingAndFalse
          keypress: (event) =>
            handlerStack.remove()
            keyChar = String.fromCharCode event.charCode
            if keyChar.length == 1
              @enterVisualModeForMovement count, immediateMovement: "l", deleteFromDocument: true, noCopyToClipboard: true
              DomUtils.simulateTextEntry @element, [0...count].map(-> keyChar).join ""
            @suppressEvent

    # Disabled: potentially confusing.
    # # If the input is empty, then enter insert mode immediately.
    # unless @element.isContentEditable
    #   if @element.value.trim() == ""
    #     @enterInsertMode()
    #     HUD.showForDuration "Input empty, entered insert mode directly.", 3500
    #
    # End of edit-mode constructor.

  # For "~", "3~", "g~3w", "g~e", and so on.
  swapCase: (count, immediate) ->
    @enterVisualModeForMovement count,
      immediateMovement: if immediate then "l" else null
      deleteFromDocument: true
      noCopyToClipboard: true
      onYank: (text) =>
        chars =
          for char in text.split ""
            if char == char.toLowerCase() then char.toUpperCase() else char.toLowerCase()
        DomUtils.simulateTextEntry @element, chars.join ""

  # For "p" and "P".
  pasteClipboard: (direction) ->
    @paste (text) =>
      if text
        # We use the following heuristic: if the text ends with a newline character, then it's a line-oriented
        # paste, and should be pasted in at a line break.
        if /\n$/.test text
          @runMovement backward, lineboundary
          @runMovement forward, line if direction == forward
          DomUtils.simulateTextEntry @element, text
          @runMovement backward, line
        else
          DomUtils.simulateTextEntry @element, text

  # For "o" and "O".
  openLine: (direction) ->
    @runMovement direction, lineboundary
    DomUtils.simulateTextEntry @element, "\n"
    @runMovement backward, character if direction == backward
    @enterInsertMode()

  # This lanches a visual-mode instance for one movement only, (usually) yanks the resulting selected text,
  # and (possibly) deletes it.
  enterVisualModeForMovement: (count, options = {}) ->
    @launchSubMode VisualMode, extend options,
      badge: "M"
      initialCountPrefix: count
      oneMovementOnly: true

  enterInsertMode: () ->
    @launchSubMode InsertMode,
      exitOnEscape: true
      targetElement: @options.targetElement

  launchSubMode: (mode, options = {}) ->
    @activeSubMode?.instance.exit()
    @activeSubMode =
      mode: mode
      options: options
      instance: new mode extend options, parentMode: @
    @activeSubMode.instance.onExit => @activeSubMode = null

  exit: (event, target) ->
    super event, target

    # Deactivate any active sub-mode. Any such mode will clear @activeSubMode on exit, so we grab a copy now.
    activeSubMode = @activeSubMode
    activeSubMode?.instance.exit()

    if event?.type == "keydown" and KeyboardUtils.isEscape event
      if target? and DomUtils.isDOMDescendant @element, target
        @element.blur()

    if event?.type == "blur"
      # This instance of edit mode has now been entirely removed from the handler stack.  It is inactive.
      # However, the user hasn't asked to leave edit mode, and may return.  For example, we get a blur event
      # when we change tab.  Or, the user may be copying text with the mouse.   When the user does return,
      # they expect to still be in edit mode.  We leave behind a "suspended-edit" mode which watches for focus
      # events and activates a new edit-mode instance if required.
      #
      # How does this get cleaned up?  It's a bit tricky.  The suspended-edit mode remains active on the
      # current input element indefinitely.  However, the only way to enter edit mode is via focusInput.  And
      # all modes launched by focusInput on a particular input element share a singleton (the element itself).
      # In addition, the new mode below shares the same singleton.  So any new insert-mode or edit-mode
      # instance on this target element (the singleton) displaces any previously-active mode (including any
      # suspended-edit mode).  PostFindMode shares the same singleton.
      #
      (new Mode name: "#{@id}-suspended", singleton: @options.singleton).push
        _name: "suspended-edit/#{@id}/focus"
        focus: (event) =>
          @alwaysContinueBubbling =>
            if event?.target == @options.targetElement
              editMode = new EditMode Utils.copyObjectOmittingProperties @options, "keydown", "keypress", "keyup"
              editMode.launchSubMode activeSubMode.mode, activeSubMode.options if activeSubMode

root = exports ? window
root.VisualMode = VisualMode
root.VisualLineMode = VisualLineMode
root.EditMode = EditMode

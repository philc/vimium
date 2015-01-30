
# Todo:
# Konami code?
# Use find as a mode.
# Exit on Ctrl-Enter.
# Scroll is broken (again).  Seems to be after dd.
# Paste of whole lines.
# Arrow keys.
# J

# This prevents printable characters from being passed through to the underlying page.  It should, however,
# allow through Chrome keyboard shortcuts.
class SuppressPrintable extends Mode
  constructor: (options = {}) ->
    handler = (event) =>
      return @stopBubblingAndTrue if not KeyboardUtils.isPrintable event
      return @suppressEvent if event.type != "keydown"
      # Completely suppress Backspace and Delete, they change the selection.
      @suppressEvent if event.keyCode in [ 8, 46 ]
      # Suppress propagation (but not preventDefault) for keydown, printable events.
      DomUtils.suppressPropagation event
      @stopBubblingAndFalse

    super extend options,
      keydown: handler
      keypress: handler
      keyup: handler

# This watches keypresses and maintains the count prefix as number keys and other keys are pressed.
class CountPrefix extends SuppressPrintable
  constructor: (options) ->
    @countPrefix = ""
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

  # This handles both "d3w" and "3dw". Also, "3d2w" deletes six words.
  getCountPrefix: ->
    count = @countPrefixFactor * if 0 < @countPrefix?.length then parseInt @countPrefix else 1
    @countPrefix = ""
    @countPrefixFactor = 1
    count

# Symbolic names for some common strings.
forward = "forward"
backward = "backward"
character = "character"
vimword = "vimword"
lineboundary= "lineboundary"

# This implements movement commands with count prefixes for both visual mode and edit mode.
class Movement extends CountPrefix
  opposite: forward: backward, backward: forward

  paste: (callback) ->
    chrome.runtime.sendMessage handler: "pasteFromClipboard", (response) -> callback response

  copy: (text, isFinalUserCopy = false) ->
    chrome.runtime.sendMessage handler: "copyToClipboard", data: text
    # If isFinalUserCopy is set, then we're copying the final text selected by the user (and exiting).
    # However, we may be called from within @protectClipboard, which will later try to restore the clipboard's
    # contents.  Therefore, we disable copy so that subsequent calls will not be propagated.
    @copy = (->) if isFinalUserCopy

  # This used whenever manipulating the selection may, as a side effect, change the clipboard's contents.  We
  # restore the original clipboard contents when we're done. May be asynchronous.  We use a lock so that calls
  # can be nested.
  protectClipboard: do ->
    locked = false

    (func) ->
      if locked then func()
      else
        locked = true
        @paste (text) =>
          func(); @copy text; locked = false

  changeMode: (mode, options = {}) ->
    @exit()
    if @options.parentMode
      @options.parentMode.launchSubMode mode, options
    else
      new mode

  # Return the character following the focus, and leave the selection unchanged.
  nextCharacter: ->
    beforeText = @selection.toString()
    if beforeText.length == 0 or @getDirection() == forward
      @selection.modify "extend", forward, character
      afterText = @selection.toString()
      @selection.modify "extend", backward, character unless beforeText == afterText
      afterText[afterText.length - 1]
    else
      beforeText[0]

  nextCharacterIsWordCharacter: ->
    /[A-Za-z0-9_]/.test @nextCharacter()

  # Run a movement.  For convenience, the following three argument forms are available:
  #   @runMovement "forward word"
  #   @runMovement [ "forward", "word" ]
  #   @runMovement "forward", "word"
  #
  # The granularities are word, "line", "lineboundary", "sentence" and "paragraph".  In addition, we implement
  # the pseudo granularity "vimword", which implements vim-like word movement, for "w".
  #
  runMovement: (args...) ->
    # Normalize the various argument forms (to an array of two strings: direction and granularity).
    movement =
      if typeof(args[0]) == "string" and args.length == 1
        args[0].trim().split /\s+/
      else
        if args.length == 1 then args[0] else args[...2]

    # Perform the movement.
    if movement[1] == vimword and movement[0] == forward
      if @nextCharacterIsWordCharacter()
        @runMovements [ forward, "word" ], [ forward, vimword ]
      else
        @runMovements [ forward, "word" ], [ backward, "word" ]

    else if movement[1] == vimword
      @selection.modify @alterMethod, backward, "word"

    else
      @selection.modify @alterMethod, movement...

  # Return a simple camparable value which depends on various aspects of the selection which may change when
  # the selection changes.  This is used to detect, after a movement, whether the selection has changed.
  hashSelection: (debug) ->
    range = @selection.getRangeAt(0)
    [ @element?.selectionStart
      @selection.toString().length
      range.anchorOffset
      range.focusOffset
      @selection.extentOffset
      @selection.baseOffset
    ].join "/"

  # Call a function; return true if the selection changed.
  selectionChanged: (func) ->
    before = @hashSelection(); func(); @hashSelection() != before

  # Run a sequence of movements, stopping if a movement fails to change the selection.
  runMovements: (movements...) ->
    for movement in movements
      return false unless @selectionChanged => @runMovement movement
    true

  # Swap the anchor node/offset and the focus node/offset (which implements "o" for visual mode).
  reverseSelection: ->
    element = document.activeElement
    direction = @getDirection()
    if element and DomUtils.isEditable(element) and not element.isContentEditable
      # Note(smblott). This implementation is unacceptably expensive if the selection is large.  We only use
      # it when we have to.  However, the normal method (below) does not work for simple text inputs.
      length = @selection.toString().length
      @collapseSelectionToFocus()
      @runMovement @opposite[direction], character for [0...length]
    else
      # Normal method.
      original = @selection.getRangeAt(0).cloneRange()
      range = original.cloneRange()
      range.collapse direction == backward
      @selectRange range
      which = if direction == forward then "start" else "end"
      @selection.extend original["#{which}Container"], original["#{which}Offset"]

  # Try to extend the selection one character in "direction".  Return 1, -1 or 0, indicating whether the
  # selection got bigger, or smaller, or is unchanged.
  extendByOneCharacter: (direction) ->
    length = @selection.toString().length
    @selection.modify "extend", direction, character
    @selection.toString().length - length

  # Get the direction of the selection.  The selection is "forward" if the focus is at or after the anchor,
  # and "backward" otherwise.
  # NOTE(smblott). Could be better, see: https://dom.spec.whatwg.org/#interface-range.
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

  selectRange: (range) ->
    @selection.removeAllRanges()
    @selection.addRange range

  # A movement can be a string (which will be passed to @runMovement() count times), or a function (which will
  # be called once with count as its argument.
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

  constructor: (options) ->
    @selection = window.getSelection()
    @movements = extend {}, @movements
    @commands = {}
    @keyQueue = ""
    @keypressCount = 0
    super options

    # Aliases.
    @movements.B = @movements.b
    @movements.W = @movements.w

    if @options.immediateMovement
      @runMovementKeyChar @options.immediateMovement, @getCountPrefix()
      return

    @push
      _name: "#{@id}/keypress"
      keypress: (event) =>
        @keypressCount += 1
        unless event.metaKey or event.ctrlKey or event.altKey
          @keyQueue += String.fromCharCode event.charCode
          # Keep at most two characters in the key queue.
          @keyQueue = @keyQueue.slice Math.max 0, @keyQueue.length - 2
          for command in [ @keyQueue, @keyQueue[1..] ]
            if command and (@movements[command] or @commands[command])
              @selection = window.getSelection()
              @keyQueue = ""

              # We need to treat "0" specially.  It can be either a movement, or a continutation of a count
              # prefix.  Don't treat it as a movement if we already have a count prefix.
              return @continueBubbling if command == "0" and 0 < @countPrefix

              if @commands[command]
                @commands[command].call @, @getCountPrefix()
                @scrollIntoView()
                return @suppressEvent

              else if @movements[command]
                @runMovementKeyChar command, @getCountPrefix()
                return @suppressEvent

        @continueBubbling

    # Install basic bindings for find mode, "n" and "N".  We do not install these bindings if this is a
    # sub-mode of edit mode, because we cannot (yet) guarantee that the selection will remain within the
    # active element.
    unless @options.parentMode or options.oneMovementOnly
      do =>
        executeFind = (count, findBackwards) =>
          if query = getFindModeQuery()
            initialRange = @selection.getRangeAt(0).cloneRange()
            for [0...count]
              unless window.find query, Utils.hasUpperCase(query), findBackwards, true, false, true, false
                HUD.showForDuration "Yanked #{@yankedText.length} character#{plural}: \"#{message}\".", 2500
                @selectRange initialRange
                @scrollIntoView()
                break

        @movements.n = (count) -> executeFind count, false
        @movements.N = (count) -> executeFind count, true
        @movements["/"] = ->
          @findMode = enterFindMode()
          @findMode.onExit => new VisualMode
    #
    # End of Movement constructor.

  runMovementKeyChar: (args...) ->
    @protectClipboard => @handleMovementKeyChar args...

  handleMovementKeyChar: (keyChar, count = 1) ->
    switch typeof @movements[keyChar]
      when "string"
        @runMovement @movements[keyChar] for [0...count]
      when "function"
        @movements[keyChar].call @, count
    @scrollIntoView()

  # Yank the selection; always exits; either deletes the selection or collapses it; returns the yanked text.
  yank: (args = {}) ->
    @yankedText = @selection.toString()

    if args.deleteFromDocument or @options.deleteFromDocument
      @selection.deleteFromDocument()
    else
      @collapseSelectionToAnchor()

    message = @yankedText.replace /\s+/g, " "
    message = message[...12] + "..." if 15 < @yankedText.length
    plural = if @yankedText.length == 1 then "" else "s"
    HUD.showForDuration "Yanked #{@yankedText.length} character#{plural}: \"#{message}\".", 2500

    @options.onYank.call @, @yankedText if @options.onYank
    @exit()
    @yankedText

  # Select a lexical entity, such as a word, or a sentence. The entity should be a movement granularity such
  # as "word" or "lineboundary".
  selectLexicalEntity: (entity, count = 1) ->
    # Locate the start of the current entity.
    @runMovement forward, entity
    @runMovement backward, entity
    @collapseSelectionToFocus() if @options.oneMovementOnly
    # Move over count entities.
    for [0...count]
      return unless @runMovements [ forward, entity ]
      # Also consume the next character. For "lineboundary", this consumes the following newline, allowing us
      # to move on to the next line (for "3dd", "3yy", etc).
      @runMovement forward, character
    # Move to the start of the subsequent entity
    @runMovements [ forward, entity ], [ backward, entity ]

  # Try to scroll the focus into view.
  scrollIntoView: ->
    @protectClipboard =>
      if @element and DomUtils.isEditable @element
        if @element.clientHeight < @element.scrollHeight
          if @element.isContentEditable
            # How do we do this?  This case matters for gmail and Google's inbox.
          else
            position = if @getDirection() == backward then @element.selectionStart else @element.selectionEnd
            coords = DomUtils.getCaretCoordinates @element, position
            Scroller.scrollToPosition @element, coords.top, coords.left
      else
        elementWithFocus = DomUtils.getElementWithFocus @selection, @getDirection() == backward
        Scroller.scrollIntoView elementWithFocus if elementWithFocus

class VisualMode extends Movement
  constructor: (options = {}) ->
    @selection = window.getSelection()
    @alterMethod = "extend"

    defaults =
      name: "visual"
      badge: "V"
      singleton: VisualMode
      exitOnEscape: true
    super extend defaults, options

    switch @selection.type
      when "None"
        HUD.showForDuration "No selection, entering caret mode first.", 2500
        return @changeMode CaretMode
      when "Caret"
        @selection.modify "extend", forward, character unless @options.oneMovementOnly

    # Yank on <Enter>.
    @push
      _name: "#{@id}/enter"
      keypress: (event) =>
        if event.keyCode == keyCodes.enter and not (event.metaKey or event.ctrlKey or event.altKey)
          @yank(); @suppressEvent
        else @continueBubbling

    # Visual-mode commands.
    unless @options.oneMovementOnly
      @commands.y = -> @yank()
      @commands.p = -> chrome.runtime.sendMessage handler: "openUrlInCurrentTab", url: @yank()
      @commands.P = -> chrome.runtime.sendMessage handler: "openUrlInNewTab", url: @yank()
      @commands.V = -> @changeMode VisualLineMode
      @commands.c = -> @changeMode CaretMode
      @commands.o = -> @reverseSelection()
      @commands.Y = (count) -> @selectLine count; @yank()

      # Additional commands when run under edit mode.
      if @options.parentMode
          @commands.x = -> @yank deleteFromDocument: true
          @commands.d = -> @yank deleteFromDocument: true
          @commands.c = -> @yank deleteFromDocument: true; @options.parentMode.enterInsertMode()

    # For edit mode's "yy" and "dd".
    if @options.yankLineCharacter
      @commands[@options.yankLineCharacter] = (count) ->
        if @keypressCount == 1
          @selectLine count
          @yank()

    # For edit mode's "daw", "cas", and so on.
    if @options.oneMovementOnly
      @commands.a = (count) ->
        if @keypressCount == 1
          for entity in [ "word", "sentence", "paragraph" ]
            do (entity) =>
              @commands[entity.charAt 0] = ->
                if @keypressCount == 2
                  @selectLexicalEntity entity, count
                  @yank()
    #
    # End of VisualMode constructor.

  exit: (event, target) ->
    unless @options.parentMode
      # Don't leave the user in insert mode just because they happen to have selected text within an input
      # element.
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement.blur()

    super event, target
    if @yankedText?
      unless @options.noCopyToClipboard
        console.log "yank:", @yankedText if @debug
        @copy @yankedText, true

  handleMovementKeyChar: (args...) ->
    super args...
    @yank() if @options.oneMovementOnly

  selectLine: (count) ->
    @reverseSelection() if @getDirection() == forward
    @runMovement backward, lineboundary
    @reverseSelection()
    @runMovement forward, "line" for [1...count]
    @runMovement forward, lineboundary
    @runMovement forward, character

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

    switch @selection.type
      when "None"
        @establishInitialSelectionAnchor()
        if @selection.type == "None"
          HUD.showForDuration "Create a selection before entering visual mode.", 2500
          @exit()
          return
      when "Range"
        @collapseSelectionToFocus()

    @selection.modify "extend", forward, character
    @scrollIntoView()

    extend @commands,
      v: -> @changeMode VisualMode
      V: -> @changeMode VisualLineMode

  handleMovementKeyChar: (args...) ->
    @collapseSelectionToAnchor()
    super args...
    @selection.modify "extend", forward, character

  # When visual mode starts and there's no existing selection, we launch CaretMode and try to establish a
  # selection.  As a heuristic, we pick the first non-whitespace character of the first visible text node
  # which seems to be long enough to be interesting.
  establishInitialSelectionAnchor: ->
    nodes = document.createTreeWalker document.body, NodeFilter.SHOW_TEXT
    while node = nodes.nextNode()
      # Don't choose short text nodes; they're likely to be part of a banner.
      if node.nodeType == 3 and 50 <= node.data.trim().length
        element = node.parentElement
        if DomUtils.getVisibleClientRect(element) and not DomUtils.isEditable element
          offset = node.data.length - node.data.replace(/^\s+/, "").length
          range = document.createRange()
          range.setStart node, offset
          range.setEnd node, offset
          @selectRange range
          return true
    false

class EditMode extends Movement
  constructor: (options = {}) ->
    @element = document.activeElement
    @alterMethod = "move"
    return unless @element and DomUtils.isEditable @element

    defaults =
      name: "edit"
      badge: "E"
      exitOnEscape: true
      exitOnBlur: @element
    super extend defaults, options

    extend @commands,
      i: -> @enterInsertMode()
      a: -> @enterInsertMode()
      I: -> @runMovement "backward lineboundary"; @enterInsertMode()
      A: -> @runMovement "forward lineboundary"; @enterInsertMode()
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

      J: (count) ->
        for [0...count]
          @runMovement forward, lineboundary
          @enterVisualModeForMovement 1, immediateMovement: "w", deleteFromDocument: true, noCopyToClipboard: true
          DomUtils.simulateTextEntry @element, " "

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

      '~': (count) -> @swapCase count, true
      'g~': (count) -> @swapCase count, false

    # Disabled as potentially confusing.
    # # If the input is empty, then enter insert mode immediately.
    # unless @element.isContentEditable
    #   if @element.value.trim() == ""
    #     @enterInsertMode()
    #     HUD.showForDuration "Input empty, entered insert mode directly.", 3500

  swapCase: (count, immediate) ->
    @enterVisualModeForMovement count,
      immediateMovement: if immediate then "l" else null
      deleteFromDocument: true
      noCopyToClipboard: true
      onYank: (text) =>
        chars =
          for char in text.split ""
            if char == char.toLowerCase()
              char.toUpperCase()
            else
              char.toLowerCase()
        DomUtils.simulateTextEntry @element, chars.join ""

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
      instance: new mode extend options, parentMode: @
    @activeSubMode.instance.onExit => @activeSubMode = null

  pasteClipboard: (direction) ->
    @paste (text) =>
      if text
        # We use the following heuristic: if the text ends in a newline character, then it's a line-oriented
        # paste, and should be pasted in at a line break.
        if /\n$/.test text
          @runMovement backward, lineboundary
          @runMovement forward, "line" if direction == forward
          DomUtils.simulateTextEntry @element, text
          @runMovement backward, "line"
        else
          DomUtils.simulateTextEntry @element, text

  openLine: (direction) ->
    @runMovement direction, lineboundary
    DomUtils.simulateTextEntry @element, "\n"
    @runMovement backward, character if direction == backward
    @enterInsertMode()

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
      # However, the user may return.  For example, we get a blur event when we change tab.  Or, the user may
      # be copying text with the mouse.   When the user does return, they expect to still be in edit mode.  We
      # leave behind a "suspended-edit" mode which watches for focus events and activates a new edit-mode
      # instance if required.
      #
      # How this gets cleaned up is a bit tricky.  The suspended-edit mode remains active on the current input
      # element indefinitely.  However, the only way to enter edit mode is via focusInput.  And all modes
      # launched by focusInput on a particular input element share a singleton (the element itself).  In
      # addition, the new mode below shares the same singleton.  So any new insert-mode or edit-mode instance
      # on this target element (the singleton) displaces any previously-active mode (including any
      # suspended-edit mode).  PostFindMode shares the same singleton.
      #
      (new Mode name: "#{@id}-suspended", singleton: @options.singleton).push
        _name: "suspended-edit/#{@id}/focus"
        focus: (event) =>
          @alwaysContinueBubbling =>
            if event?.target == @options.targetElement
              editMode = new EditMode @getConfigurationOptions()
              if activeSubMode
                editMode.launchSubMode activeSubMode.mode, activeSubMode.instance.getConfigurationOptions()

root = exports ? window
root.VisualMode = VisualMode
root.VisualLineMode = VisualLineMode
root.EditMode = EditMode

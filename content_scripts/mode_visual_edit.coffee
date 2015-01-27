
# Todo:
# Konami code?
# Use find as a mode.
# Perhaps refactor visual/movement modes.
# FocusInput selector is currently broken.

# This prevents printable characters from being passed through to the underlying page.  It should, however,
# allow through Chrome keyboard shortcuts.  It's a keyboard-event backstop for visual mode and edit mode.
class SuppressPrintable extends Mode
  constructor: (options = {}) ->
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
          @suppressEvent
      else
        @stopBubblingAndTrue

    super extend options,
      keydown: handler
      keypress: handler
      keyup: handler

# This watches keyboard events and maintains @countPrefix as number keys and other keys are pressed.
class CountPrefix extends SuppressPrintable
  constructor: (options) ->
    super options

    @countPrefix = ""
    @countPrefixFactor = 1
    @countPrefixFactor = @getCountPrefix options.initialCountPrefix if options.initialCountPrefix

    @push
      _name: "#{@id}/maintain-count"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            @countPrefix =
              if keyChar?.length == 1 and "0" <= keyChar <= "9" and @countPrefix + keyChar != "0"
                @countPrefix + keyChar
              else
                ""

  # This handles both "d3w" and "3dw". Also, "3d2w" deletes six words.
  getCountPrefix: (prefix = @countPrefix) ->
    prefix = prefix.toString() if typeof prefix == "number"
    count = @countPrefixFactor * if 0 < prefix?.length then parseInt prefix else 1
    @countPrefix = ""
    @countPrefixFactor = 1
    count

# Some symbolic names for widely-used strings.
forward = "forward"
backward = "backward"
character = "character"

# This implements movement commands with count prefixes (using CountPrefix) for both visual mode and edit
# mode.
class Movement extends CountPrefix
  opposite: forward: backward, backward: forward

  copy: (text) ->
    chrome.runtime.sendMessage handler: "copyToClipboard", data: text if text

  paste: (callback) ->
    chrome.runtime.sendMessage handler: "pasteFromClipboard", (response) -> callback response

  # Return a value which changes whenever the selection changes, regardless of whether the selection is
  # collapsed.
  hashSelection: ->
    [ @element?.selectionStart, @selection.toString().length ].join "/"

  # Call a function; return true if the selection changed.
  selectionChanged: (func) ->
    before = @hashSelection(); func(); @hashSelection() != before

  # Run a movement.  The arguments can be one of the following forms:
  #   - "forward word" (one argument, a string)
  #   - [ "forward", "word" ] (one argument, not a string)
  #   - "forward", "word" (two arguments)
  runMovement: (args...) ->
    movement =
      if typeof(args[0]) == "string" and args.length == 1
        args[0].trim().split /\s+/
      else
        if args.length == 1 then args[0] else args[...2]
    @selection.modify @alterMethod, movement...

  # Run a sequence of movements, stopping if a movement fails to change the selection.
  runMovements: (movements...) ->
    for movement in movements
      return false unless @selectionChanged => @runMovement movement
    true

  # Swap the anchor node/offset and the focus node/offset.
  reverseSelection: ->
    element = document.activeElement
    if element and DomUtils.isEditable(element) and not element.isContentEditable
      # Note(smblott). This implementation is unacceptably inefficient if the selection is large.  We only use
      # it if we have to.  However, the normal method (below) does not work for input elements.
      direction = @getDirection()
      length = @selection.toString().length
      @collapseSelectionToFocus()
      @runMovement @opposite[direction], character for [0...length]
    else
      # Normal method.
      direction = @getDirection()
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

  # An approximation of the vim "w" movement; only ever used in the forward direction.  The last two character
  # movements allow us to also get to the end of the very-last word.
  moveForwardWord: () ->
    # First, move to the end of the preceding word...
    if @runMovements "forward character", "backward word", "forward word"
      # And then to the start of the following word...
      @runMovements "forward word", "forward character", "backward character", "backward word"

  collapseSelectionToAnchor: ->
    if 0 < @selection.toString().length
      @selection[if @getDirection() == backward then "collapseToEnd" else "collapseToStart"]()

  collapseSelectionToFocus: ->
    if 0 < @selection.toString().length
      @selection[if @getDirection() == forward then "collapseToEnd" else "collapseToStart"]()

  selectRange: (range) ->
    @selection.removeAllRanges()
    @selection.addRange range

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
    "Y": -> @selectLexicalEntity "lineboundary"
    "o": -> @reverseSelection()

  constructor: (options) ->
    @selection = window.getSelection()
    @movements = extend {}, @movements
    @commands = {}
    @keyQueue = ""
    @keypressCount = 0
    @yankedText = ""
    super options

    # Aliases.
    @movements.B = @movements.b
    @movements.W = @movements.w

    if @options.immediateMovement
      # This instance has been created just to run a single movement only and then yank the result.
      @handleMovementKeyChar @options.immediateMovement
      @yank()
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

              if @commands[command]
                @commands[command].call @, @getCountPrefix()
                @scrollIntoView()
                return @suppressEvent

              else if @movements[command]
                @handleMovementKeyChar command, @getCountPrefix()
                @yank() if @options.oneMovementOnly
                return @suppressEvent

        @continueBubbling

  handleMovementKeyChar: (keyChar, count = 1) ->
    action =
      switch typeof @movements[keyChar]
        when "string" then => @runMovement @movements[keyChar]
        when "function" then => @movements[keyChar].call @
    @protectClipboard =>
      action() for [0...count]
      @scrollIntoView()

  # Yank the selection; always exits; returns the yanked text.
  yank: (args = {}) ->
    @yankedText = @selection.toString()
    @selection.deleteFromDocument() if args.deleteFromDocument or @options.deleteFromDocument
    console.log "yank:", @yankedText if @debug

    message = @yankedText.replace /\s+/g, " "
    length = @yankedText.length
    message = message[...12] + "..." if 15 < length
    plural = if length == 1 then "" else "s"
    HUD.showForDuration "Yanked #{length} character#{plural}: \"#{message}\".", 2500

    @options.onYank.call @, @yankedText if @options.onYank
    @exit()
    @yankedText

  # Select a lexical entity, such as a word, a line, or a sentence. The entity should be a Chrome movement
  # type, such as "word" or "lineboundary".  This assumes that the selection is initially collapsed.
  selectLexicalEntity: (entity) ->
    @runMovement forward, entity
    @selection.collapseToEnd()
    @runMovement backward, entity
    # Move the end of the preceding entity.
    @runMovements [ backward, entity ], [ forward, entity ]

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
        elementWithFocus = @getElementWithFocus @selection
        Scroller.scrollIntoView elementWithFocus if elementWithFocus

  # Adapted from: http://roysharon.com/blog/37.
  # I have no idea how this works (smblott, 2015/1/22).
  # The intention is to find the element containing the focus.  That's the element we need to scroll into
  # view.
  getElementWithFocus: (selection) ->
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

class VisualMode extends Movement
  constructor: (options = {}) ->
    @selection = window.getSelection()
    @alterMethod = "extend"

    switch @selection.type
      when "None"
        unless @establishInitialSelection()
          HUD.showForDuration "Create a selection before entering visual mode.", 2500
          return
      when "Caret"
        # Try to start with a visible selection.
        @extendByOneCharacter(forward) or @extendByOneCharacter backward unless options.editModeParent
        @scrollIntoView() if @selection.type == "Range"

    defaults =
      name: "visual"
      badge: "V"
      singleton: VisualMode
      exitOnEscape: true
    super extend defaults, options

    # Additional commands when not being run only for movement.
    unless @options.oneMovementOnly
      @commands.y = -> @yank()
      @commands.V = -> new VisualLineMode
      @commands.p = -> chrome.runtime.sendMessage handler: "openUrlInCurrentTab", url: @yank()
      @commands.P = -> chrome.runtime.sendMessage handler: "openUrlInNewTab", url: @yank()

    # Additional commands when run under edit mode (but not just for movement).
    if @options.editModeParent and not @options.oneMovementOnly
        @commands.x = -> @yank deleteFromDocument: true
        @commands.d = -> @yank deleteFromDocument: true
        @commands.c = ->
          @yank deleteFromDocument: true
          @options.editModeParent.enterInsertMode()

    # For "yy" and "dd".
    if @options.yankLineCharacter
      @commands[@options.yankLineCharacter] = ->
        if @keypressCount == 1
          @selectLexicalEntity "lineboundary"
          @yank()

    # For "daw", "cas", and so on.
    if @options.oneMovementOnly
      @commands.a = ->
        if @keypressCount == 1
          for entity in [ "word", "sentence", "paragraph" ]
            do (entity) =>
              @movements[entity.charAt 0] = ->
                if @keypressCount == 2
                  @selectLexicalEntity entity
                  @yank()

    unless @options.editModeParent
      @installFindMode()

    # Grab the initial clipboard contents.  We try to keep them intact until we get an explicit yank.
    @clipboardContents = ""
    @paste (text) =>
      @clipboardContents = text if text
    #
    # End of VisualMode constructor.

  # This used whenever manipulating the selection may, as a side effect, change the clipboard contents.  We
  # always reinstall the original clipboard contents when we're done.
  protectClipboard: (func) ->
    func()
    @copy @clipboardContents if @clipboardContents

  copy: (text) ->
    super @clipboardContents = text

  exit: (event, target) ->
    @collapseSelectionToAnchor() if @yankedText or @options.editModeParent

    unless @options.editModeParent
      # Don't leave the user in insert mode just because they happen to have selected text within an input
      # element.
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement.blur()

    super event, target
    @copy @yankedText if @yankedText

  # FIXME(smblott).  This is a mess, it needs to be reworked.  Ideally, incorporate FindMode.
  installFindMode: ->
    previousFindRange = null

    executeFind = (findBackwards) =>
      query = getFindModeQuery()
      if query
        caseSensitive = Utils.hasUpperCase query
        @protectClipboard =>
          initialRange = @selection.getRangeAt(0).cloneRange()
          direction = @getDirection()

          # Re-selecting the previous match, if any; this tells Chrome where to start.
          @selectRange previousFindRange if previousFindRange

          window.find query, caseSensitive, findBackwards, true, false, true, false
          previousFindRange = newFindRange = @selection.getRangeAt(0).cloneRange()
          # FIXME(smblott).  What if there are no matches?

          # Install a new range from the original selection anchor to end of the new match.
          range = document.createRange()
          which = if direction == forward then "start" else "end"
          range.setStart initialRange["#{which}Container"], initialRange["#{which}Offset"]
          range.setEnd newFindRange.endContainer, newFindRange.endOffset
          @selectRange range

          # If we're now going backwards (or if the selection is empty), then extend the selection to include
          # the match itself.
          if @getDirection() == backward or @selection.toString().length == 0
            range.setStart newFindRange.startContainer, newFindRange.startOffset
            @selectRange range

    @movements.n = -> executeFind false
    @movements.N = -> executeFind true

  # When visual mode starts and there's no existing selection, we try to establish one.  As a heuristic, we
  # pick the first non-whitespace character of the first visible text node which seems to be long enough to be
  # interesting.
  establishInitialSelection: ->
    nodes = document.createTreeWalker document.body, NodeFilter.SHOW_TEXT
    while node = nodes.nextNode()
      # Don't pick really short texts; they're likely to be part of a banner.
      if node.nodeType == 3 and 50 <= node.data.trim().length
        element = node.parentElement
        if DomUtils.getVisibleClientRect(element) and not DomUtils.isEditable element
          offset = node.data.length - node.data.replace(/^\s+/, "").length
          range = document.createRange()
          range.setStart node, offset
          range.setEnd node, offset + 1
          @selectRange range
          @scrollIntoView()
          return true
    false

class VisualLineMode extends VisualMode
  constructor: (options = {}) ->
    super extend { name: "visual/line" }, options
    @extendSelection()

  handleMovementKeyChar: (keyChar) ->
    super keyChar
    @extendSelection()

  extendSelection: ->
    initialDirection = @getDirection()
    for direction in [ initialDirection, @opposite[initialDirection] ]
      @runMovement direction, "lineboundary"
      @reverseSelection()

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
      A: -> @runMovement "forward lineboundary"; @enterInsertMode()
      o: -> @openLine forward
      O: -> @openLine backward
      p: -> @pasteClipboard forward
      P: -> @pasteClipboard backward
      v: -> @launchSubMode VisualMode

      Y: -> @enterVisualModeForMovement immediateMovement: "Y"
      x: -> @enterVisualModeForMovement immediateMovement: "h", deleteFromDocument: true
      X: -> @enterVisualModeForMovement immediateMovement: "l", deleteFromDocument: true
      y: -> @enterVisualModeForMovement yankLineCharacter: "y"
      d: -> @enterVisualModeForMovement yankLineCharacter: "d", deleteFromDocument: true
      c: -> @enterVisualModeForMovement deleteFromDocument: true, onYank: => @enterInsertMode()

      D: -> @enterVisualModeForMovement immediateMovement: "$", deleteFromDocument: true
      C: -> @enterVisualModeForMovement immediateMovement: "$", deleteFromDocument: true, onYank: => @enterInsertMode()

    # Disabled as potentially confusing.
    # # If the input is empty, then enter insert mode immediately.
    # unless @element.isContentEditable
    #   if @element.value.trim() == ""
    #     @enterInsertMode()
    #     HUD.showForDuration "Input empty, entered insert mode directly.", 3500

  enterVisualModeForMovement: (options = {}) ->
    @launchSubMode VisualMode, extend options,
      badge: "M"
      initialCountPrefix: @getCountPrefix()
      oneMovementOnly: true

  enterInsertMode: () ->
    @launchSubMode InsertMode,
      exitOnEscape: true
      targetElement: @options.targetElement

  launchSubMode: (mode, options = {}) ->
    @lastSubMode =
      mode: mode
      instance: new mode extend options, editModeParent: @

  pasteClipboard: (direction) ->
    @paste (text) =>
      DomUtils.simulateTextEntry @element, text if text

  openLine: (direction) ->
    @runMovement direction, "lineboundary"
    @enterInsertMode()
    DomUtils.simulateTextEntry @element, "\n"
    @runMovement backward, character if direction == backward

  # This used whenever manipulating the selection may, as a side effect, change the clipboard contents.  We
  # always reinstall the original clipboard contents when we're done. Note, this may be asynchronous.  We do
  # this this way (as opposed to the simpler, synchronous method used by Visual mode) because the user may
  # wish to select text with the mouse (while edit mode is active) to later paste with "p" or "P".
  protectClipboard: do ->
    locked = false

    (func) ->
      if locked
        func()
      else
        locked = true
        @paste (text) =>
          func()
          @copy text
          locked = false

  exit: (event, target) ->
    super event, target

    @lastSubMode =
      if @lastSubMode?.instance.modeIsActive
        @lastSubMode.instance.exit event, target
        @lastSubMode

    if event?.type == "keydown" and KeyboardUtils.isEscape event
      if target? and DomUtils.isDOMDescendant @element, target
        @element.blur()

    if event?.type == "blur"
      # This instance of edit mode has now been entirely removed from the handler stack.  It is inactive.
      # However, the user may return.  For example, we get a blur event when we change tabs.  Or, the user may
      # be copying text with the mouse.   When the user does return, they expect to still be in edit mode.  We
      # leave behind a "suspended-edit" mode which watches for focus events and activates a new edit-mode
      # instance if required.
      #
      # How this gets cleaned up is a bit tricky.  The suspended-edit mode remains active on the current input
      # element indefinately.  However, the only way to enter edit mode is via focusInput.  And all modes
      # launched by focusInput on a particular input element share a singleton (the element itself).  In
      # addition, the new mode below shares the same singleton.  So a newly-activated insert-mode or
      # edit-mode instance on this target element (the singleton) displaces any previously-active mode
      # (including any suspended-edit mode).  PostFindMode shares the same singleton.
      #
      suspendedEditmode = new Mode
        name: "#{@id}-suspended"
        singleton: @options.singleton

      suspendedEditmode.push
        _name: "suspended-edit/#{@id}/focus"
        focus: (event) =>
          @alwaysContinueBubbling =>
            if event?.target == @options.targetElement
              console.log "#{@id}: reactivating edit mode" if @debug
              editMode = new EditMode @getConfigurationOptions()
              if @lastSubMode
                editMode.launchSubMode @lastSubMode.mode, @lastSubMode.instance.getConfigurationOptions()

root = exports ? window
root.VisualMode = VisualMode
root.VisualLineMode = VisualLineMode
root.EditMode = EditMode

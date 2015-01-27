
# Todo:
# Fix word movement, particularly for "a word".
# Konami code?
# Use find as a mode.

# This prevents printable characters from being passed through to underlying page.  It should, however, allow
# through chrome keyboard shortcuts.  It's a keyboard-event backstop for all of the following modes.
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
          @suppressEvent
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
    chrome.runtime.sendMessage handler: "copyToClipboard", data: text if text

  paste: (callback) ->
    chrome.runtime.sendMessage handler: "pasteFromClipboard", (response) -> callback response

  # Return a value which changes whenever the selection changes, regardless of whether the selection is
  # collapsed or not.
  hashSelection: ->
    [ @element?.selectionStart, @selection.toString().length ].join "/"

  # Call a function.  Return true if the selection changed as a side effect, false otherwise.
  selectionChanged: (func) ->
    before = @hashSelection()
    func()
    console.log before, @hashSelection()
    @hashSelection() != before

  # Run a movement.  The single movement argument can be a string of the form "direction amount", e.g.
  # "forward word", or a list, e.g. [ "forward", "word" ].
  runMovement: (movement) ->
    movement = movement.split(" ") if typeof movement == "string"
    console.log movement.join " "
    @selection.modify @alterMethod, movement...

  # Run a sequence of movements, stopping if a movement fails to change the selection.
  runMovements: (movements...) ->
    for movement in movements
      return false unless @selectionChanged => @runMovement movement
    true

  # Swap the anchor node/offset and the focus node/offset.
  reverseSelection: ->
    element = document.activeElement
    if element and DomUtils.isEditable(element) and not element. isContentEditable
      # Note(smblott). This implementation is unacceptably inefficient if the selection is large.  We only use
      # it if we have to.  However, the normal method does not work for input elements.
      direction = @getDirection()
      length = @selection.toString().length
      @selection[if direction == forward then "collapseToEnd" else "collapseToStart"]()
      @selection.modify "extend", @opposite[direction], character for [0...length]
    else
      # Normal method.
      direction = @getDirection()
      original = @selection.getRangeAt(0).cloneRange()
      range = original.cloneRange()
      range.collapse direction == backward
      @selection.removeAllRanges()
      @selection.addRange range
      which = if direction == forward then "start" else "end"
      @selection.extend original["#{which}Container"], original["#{which}Offset"]

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
    backward

  # An approximation of the vim "w" movement; only ever used in the forward direction.  The extra character
  # movements at the end allow us to also get to the end of the very-last word.
  moveForwardWord: () ->
    # First, move to the end of the preceding word...
    if @runMovements "forward character", "backward word", "forward word"
      # And then to the start of the following word...
      @runMovements "forward word", "forward character", "backward character", "backward word"

  collapseSelection: ->
    if 0 < @selection.toString().length
      @selection[if @getDirection() == backward then "collapseToEnd" else "collapseToStart"]()

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
    @alterMethod = options.alterMethod || "extend"
    @keyQueue = ""
    @keyPressCount = 0
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
        @keyPressCount += 1
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
    console.log "yank:", @yankedText if @debug

    message = @yankedText.replace /\s+/g, " "
    length = message.length
    message = message[...12] + "..." if 15 < length
    plural = if length == 1 then "" else "s"
    HUD.showForDuration "Yanked #{length} character#{plural}: \"#{message}\".", 2500

    @options.onYank.call @, @yankedText if @options.onYank
    @exit()
    @yankedText

  # Select a lexical entity, such as a word, a line, or a sentence. The argument should be a movement target,
  # such as "word" or "lineboundary".
  selectLexicalEntity: (entity) ->
    for direction in [ backward, forward ]
      @reverseSelection()
      @runMovement [ direction, entity ]

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
  # view. It seems to work most (but not all) of the time.
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

    switch @selection.type
      when "None"
        unless @establishInitialSelection()
          HUD.showForDuration "Create a selection before entering visual mode.", 2500
          return
      when "Caret"
        # Try to start with a visible selection.
        @moveInDirection(forward) or @moveInDirection backward unless options.editModeParent
        @scrollIntoView() if @selection.type == "Range"

    defaults =
      name: "visual"
      badge: "V"
      singleton: VisualMode
      exitOnEscape: true
      alterMethod: "extend"
    super extend defaults, options

    unless @options.oneMovementOnly
      extend @commands,
        "V": -> new VisualLineMode
        "y": -> @yank()

    # "P" and "p" to copy-and-go (but not under edit mode).
    unless @options.editModeParent
      do =>
        yankAndOpenAsUrl = (handler) =>
          chrome.runtime.sendMessage handler: handler, url: @yank()

        extend @commands,
          "p": -> yankAndOpenAsUrl "openUrlInCurrentTab"
          "P": -> yankAndOpenAsUrl "openUrlInNewTab"

    # Additional commands when run under edit mode.
    if @options.editModeParent and not @options.oneMovementOnly
      extend @commands,
        "c": -> @yank deleteFromDocument: true; @options.editModeParent.enterInsertMode()
        "x": -> @yank deleteFromDocument: true
        "d": -> @yank deleteFromDocument: true

    # For "yy".
    if @options.yYanksLine
      @commands.y = ->
        if @keyPressCount == 1
          @selectLexicalEntity "lineboundary"
          @yank()

    # For "dd".
    if @options.dYanksLine
      @commands.d = ->
        if @keyPressCount == 1
          @selectLexicalEntity "lineboundary"
          @yank deleteFromDocument: true

    # For "daw", "das", "dap", "caw", "cas", "cap".
    if @options.oneMovementOnly
      @commands.a = ->
        if @keyPressCount == 1
          for entity in [ "word", "sentence", "paragraph" ]
            do (entity) => @movements[entity.charAt 0] = -> @selectLexicalEntity entity

    unless @options.editModeParent
      @installFindMode()

    # Grab the initial clipboard contents.  We'll try to keep them intact until we get an explicit yank.
    @clipboardContents = ""
    @paste (text) =>
      @clipboardContents = text if text
    #
    # End of VisualMode constructor.

  protectClipboard: (func) ->
    func()
    @copy @clipboardContents if @clipboardContents

  copy: (text) ->
    super @clipboardContents = text

  exit: (event, target) ->
    if @options.editModeParent
      if event?.type == "keydown" and KeyboardUtils.isEscape event
        # Return to a caret for edit mode.
        @collapseSelection()

    @collapseSelection() if @yankedText

    unless @options.editModeParent
      # Don't leave the user in insert mode just because they happen to have selected text within an input
      # element.
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement.blur()

    super event, target
    # Copying the yanked text to the clipboard must be the very last thing we do, because other operations
    # (like collapsing the selection) interfere with the clipboard.
    @copy @yankedText if @yankedText


  installFindMode: ->
    previousFindRange = null

    executeFind = (findBackwards) =>
      query = getFindModeQuery()
      if query
        caseSensitive = Utils.hasUpperCase query
        @protectClipboard =>
          initialRange = @selection.getRangeAt(0).cloneRange()
          direction = @getDirection()

          # Start by re-selecting the previous match, if any.  This tells Chrome where to start from.
          if previousFindRange
            @selection.removeAllRanges()
            @selection.addRange previousFindRange

          window.find query, caseSensitive, findBackwards, true, false, true, false
          previousFindRange = newFindRange = @selection.getRangeAt(0).cloneRange()
          # FIXME(smblott).  What if there were no matches?

          # Now, install a range from the original selection to the new match.
          range = document.createRange()
          which = if direction == forward then "start" else "end"
          range.setStart initialRange["#{which}Container"], initialRange["#{which}Offset"]
          range.setEnd newFindRange.endContainer, newFindRange.endOffset
          @selection.removeAllRanges()
          @selection.addRange range

          # If we're going backwards (or if the election ended up empty), then extend the selection again,
          # this time to include the match itself.
          if @getDirection() == backward or @selection.toString().length == 0
            range.setStart newFindRange.startContainer, newFindRange.startOffset
            @selection.removeAllRanges()
            @selection.addRange range

    extend @movements,
      "n": -> executeFind false
      "N": -> executeFind true

  establishInitialSelection: ->
    nodes = document.createTreeWalker document.body, NodeFilter.SHOW_TEXT
    while node = nodes.nextNode()
      # Try not to pick really small nodes.  They're likely to be part of a banner.
      if node.nodeType == 3 and 50 <= node.data.trim().length
        element = node.parentElement
        if DomUtils.getVisibleClientRect(element) and not DomUtils.isEditable element
          range = document.createRange()
          text = node.data
          trimmed = text.replace /^\s+/, ""
          offset = text.length - trimmed.length
          range.setStart node, offset
          range.setEnd node, offset + 1
          @selection.removeAllRanges()
          @selection.addRange range
          @scrollIntoView()
          return true
    false

class VisualLineMode extends VisualMode
  constructor: (options = {}) ->
    options.name ||= "visual/line"
    super options
    unless @selection?.type == "None"
      @selectLexicalEntity "lineboundary"

  handleMovementKeyChar: (keyChar) ->
    super keyChar
    @runMovement "#{@getDirection()} lineboundary", true

class EditMode extends Movement
  constructor: (options = {}) ->
    @element = document.activeElement
    return unless @element and DomUtils.isEditable @element

    defaults =
      name: "edit"
      badge: "E"
      exitOnEscape: true
      exitOnBlur: @element
      alterMethod: "move"
    super extend defaults, options

    extend @commands,
      "i": -> @enterInsertMode()
      "a": -> @enterInsertMode()
      "A": -> @runMovement "forward lineboundary"; @enterInsertMode()
      "o": -> @openLine forward
      "O": -> @openLine backward
      "p": -> @pasteClipboard forward
      "P": -> @pasteClipboard backward
      "v": -> @launchSubMode VisualMode

      "Y": -> @enterVisualModeForMovement runMovement: "Y"
      "x": -> @enterVisualModeForMovement runMovement: "h", deleteFromDocument: true
      "y": -> @enterVisualModeForMovement yYanksLine: true
      "d": -> @enterVisualModeForMovement deleteFromDocument: true, dYanksLine: true
      "c": -> @enterVisualModeForMovement deleteFromDocument: true, onYank: => @enterInsertMode()

      "D": -> @enterVisualModeForMovement runMovement: "$", deleteFromDocument: true
      "C": -> @enterVisualModeForMovement runMovement: "$", deleteFromDocument: true, onYank: => @enterInsertMode()

      # Disabled as potentially confusing.
      # # If the input is empty, then enter insert mode immediately
      # unless @element.isContentEditable
      #   if @element.value.trim() == ""
      #     @enterInsertMode()
      #     HUD.showForDuration "Input empty, entered insert mode directly.", 3500

  enterVisualModeForMovement: (options = {}) ->
    @launchSubMode VisualMode, extend options,
      badge: "M"
      initialCount: @countPrefix
      oneMovementOnly: true
    @countPrefix = ""

  enterInsertMode: () ->
    @launchSubMode InsertMode,
      exitOnEscape: true
      targetElement: @options.targetElement

  launchSubMode: (mode, options = {}) ->
    @lastSubMode =
      mode: mode
      instance: Mode.cloneMode mode, extend options, editModeParent: @

  pasteClipboard: (direction) ->
    @paste (text) =>
      DomUtils.simulateTextEntry @element, text if text

  openLine: (direction) ->
    @runMovement "#{direction} lineboundary"
    @enterInsertMode()
    DomUtils.simulateTextEntry @element, "\n"
    @runMovement "backward character" if direction == backward

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

  exit: (event, target) ->
    super event, target

    lastSubMode =
      if @lastSubMode?.instance.modeIsActive
        @lastSubMode.instance.exit event, target
        @lastSubMode

    if event?.type == "keydown" and KeyboardUtils.isEscape event
      if target? and DomUtils.isDOMDescendant @element, target
        @element.blur()

    if event?.type == "blur"
      new SuspendedEditMode @options, lastSubMode

# In edit mode, the input blurs if the user changes tabs or clicks outside of the element.  In the former
# case, the user expects to remain in edit mode when they return.  In the latter case, they may just be
# copying some text with the mouse/Ctrl-C, and again they expect to remain in edit mode.  SuspendedEditMode
# monitors various events and tries to either exit completely or re-enter edit mode, as appropriate.
class SuspendedEditMode extends Mode
  constructor: (editModeOptions, lastSubMode = null) ->
    super
      name: "suspended-edit"
      singleton: editModeOptions.singleton

    @push
      _name: "#{@id}/monitor"
      focus: (event) =>
        @alwaysContinueBubbling =>
          if event?.target == editModeOptions.targetElement
            console.log "#{@id}: reactivating edit mode" if @debug
            editMode = Mode.cloneMode EditMode, editModeOptions
            if lastSubMode
              editMode.launchSubMode lastSubMode.mode, lastSubMode.instance.options
      keypress: (event) =>
        @alwaysContinueBubbling =>
          @exit() unless event.metaKey or event.ctrlKey or event.altKey

root = exports ? window
root.VisualMode = VisualMode
root.VisualLineMode = VisualLineMode
root.EditMode = EditMode

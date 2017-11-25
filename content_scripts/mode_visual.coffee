
# Symbolic names for some common strings.
forward = "forward"; backward = "backward"; character = "character"; word = "word"; line = "line"
sentence = "sentence"; paragraph = "paragraph"; vimword = "vimword"; lineboundary= "lineboundary"

# This implements various selection movements.
class Movement
  opposite: forward: backward, backward: forward

  constructor: (@alterMethod) ->
    @selection = window.getSelection()

  # Return the character following (to the right of) the focus, and leave the selection unchanged, or return
  # undefined.
  getNextForwardCharacter: ->
    beforeText = @selection.toString()
    if beforeText.length == 0 or @getDirection() == forward
      @selection.modify "extend", forward, character
      afterText = @selection.toString()
      if beforeText != afterText
        @selection.modify "extend", backward, character
        afterText[afterText.length - 1]
    else
      beforeText[0] # The existing range selection is backwards.

  # Test whether the character following the focus is a word character (and leave the selection unchanged).
  nextCharacterIsWordCharacter: do ->
    regexp = null
    ->
      # This regexp matches "word" characters.
      # From http://stackoverflow.com/questions/150033/regular-expression-to-match-non-english-characters.
      regexp ||= /[_0-9\u0041-\u005A\u0061-\u007A\u00AA\u00B5\u00BA\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u0527\u0531-\u0556\u0559\u0561-\u0587\u05D0-\u05EA\u05F0-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u08A0\u08A2-\u08AC\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0977\u0979-\u097F\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C33\u0C35-\u0C39\u0C3D\u0C58\u0C59\u0C60\u0C61\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D05-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D60\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E87\u0E88\u0E8A\u0E8D\u0E94-\u0E97\u0E99-\u0E9F\u0EA1-\u0EA3\u0EA5\u0EA7\u0EAA\u0EAB\u0EAD-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F4\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u1700-\u170C\u170E-\u1711\u1720-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1877\u1880-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191C\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19C1-\u19C7\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4B\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1CE9-\u1CEC\u1CEE-\u1CF1\u1CF5\u1CF6\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2183\u2184\u2C00-\u2C2E\u2C30-\u2C5E\u2C60-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005\u3006\u3031-\u3035\u303B\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312D\u3131-\u318E\u31A0-\u31BA\u31F0-\u31FF\u3400-\u4DB5\u4E00-\u9FCC\uA000-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA697\uA6A0-\uA6E5\uA717-\uA71F\uA722-\uA788\uA78B-\uA78E\uA790-\uA793\uA7A0-\uA7AA\uA7F8-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA80-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uABC0-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC]/
      regexp.test @getNextForwardCharacter()

  # Run a movement.  This is the core movement method, all movements happen here.  For convenience, the
  # following three argument forms are supported:
  #   @runMovement "forward word"
  #   @runMovement ["forward", "word"]
  #   @runMovement "forward", "word"
  #
  # The granularities are word, "character", "line", "lineboundary", "sentence" and "paragraph".  In addition,
  # we implement the pseudo granularity "vimword", which implements vim-like word movement (e.g. "w").
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

  # Return a simple comparable value which depends on various aspects of the selection.  This is used to
  # detect, after a movement, whether the selection has changed.
  hashSelection: ->
    range = @selection.getRangeAt(0)
    [ @selection.toString().length, range.anchorOffset, range.focusOffset, @selection.extentOffset,
      @selection.baseOffset ].join "/"

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
      # Note(smblott). This implementation is expensive if the selection is large.  We only use it here
      # because the normal method (below) does not work within text areas, etc.
      length = @selection.toString().length
      @collapseSelectionToFocus()
      @runMovement @opposite[direction], character for [0...length]
    else
      # Normal method.
      original = @selection.getRangeAt(0).cloneRange()
      range = original.cloneRange()
      range.collapse direction == backward
      @setSelectionRange range
      which = if direction == forward then "start" else "end"
      @selection.extend original["#{which}Container"], original["#{which}Offset"]

  # Try to extend the selection by one character in direction.  Return positive, negative or 0, indicating
  # whether the selection got bigger, or smaller, or is unchanged.
  extendByOneCharacter: (direction) ->
    length = @selection.toString().length
    @selection.modify "extend", direction, character
    @selection.toString().length - length

  # Get the direction of the selection.  The selection is "forward" if the focus is at or after the anchor,
  # and "backward" otherwise.
  # NOTE(smblott). This could be better, see: https://dom.spec.whatwg.org/#interface-range (however, that
  # probably wouldn't work for inputs).
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

  # For "aw", "as".  We don't do "ap" (for paragraphs), because Chrome paragraph movements are weird.
  selectLexicalEntity: (entity, count = 1) ->
    @collapseSelectionToFocus()
    @runMovement [ forward, character ] if entity == word # This makes word movements a bit more vim-like.
    @runMovement [ backward, entity ]
    @collapseSelectionToFocus()
    @runMovement [ forward, entity ] for [0...count] by 1

  selectLine: (count) ->
    # Even under caret mode, we still need an extended selection here.
    @alterMethod = "extend"
    @reverseSelection() if @getDirection() == forward
    @runMovement backward, lineboundary
    @reverseSelection()
    @runMovement forward, line for [1...count] by 1
    @runMovement forward, lineboundary
    # Include the next character if that character is a newline.
    @runMovement forward, character if @getNextForwardCharacter() == "\n"

  # Scroll the focus into view.
  scrollIntoView: ->
    unless DomUtils.getSelectionType(@selection) == "None"
      elementWithFocus = DomUtils.getElementWithFocus @selection, @getDirection() == backward
      Scroller.scrollIntoView elementWithFocus if elementWithFocus

class VisualMode extends KeyHandlerMode
  # A movement can be either a string or a function.
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

    "aw": (count) -> @movement.selectLexicalEntity word, count
    "as": (count) -> @movement.selectLexicalEntity sentence, count

    "n": (count) -> @find count, false
    "N": (count) -> @find count, true
    "/": ->
      @exit()
      new FindMode(returnToViewport: true).onExit -> new VisualMode

    "y": -> @yank()
    "Y": (count) -> @movement.selectLine count; @yank()
    "p": -> chrome.runtime.sendMessage handler: "openUrlInCurrentTab", url: @yank()
    "P": -> chrome.runtime.sendMessage handler: "openUrlInNewTab", url: @yank()
    "v": -> new VisualMode
    "V": -> new VisualLineMode
    "c": ->
      # If we're already in caret mode, or if the selection looks the same as it would in caret mode, then
      # callapse to anchor (so that the caret-mode selection will seem unchanged).  Otherwise, we're in visual
      # mode and the user has moved the focus, so collapse to that.
      if @name == "caret" or @selection.toString().length <= 1
        @movement.collapseSelectionToAnchor()
      else
        @movement.collapseSelectionToFocus()
      new CaretMode
    "o": -> @movement.reverseSelection()

  constructor: (options = {}) ->
    @movement = new Movement options.alterMethod ? "extend"
    @selection = @movement.selection

    # Build the key mapping structure required by KeyHandlerMode.  This only handles one- and two-key
    # mappings.
    keyMapping = {}
    for own keys, movement of @movements
      movement = movement.bind this if "function" == typeof movement
      if keys.length == 1
        keyMapping[keys] = command: movement
      else # keys.length == 2
        keyMapping[keys[0]] ?= {}
        extend keyMapping[keys[0]], "#{keys[1]}": command: movement

    # Aliases and complex bindings.
    extend keyMapping,
      "B": keyMapping.b
      "W": keyMapping.w
      "<c-e>": command: (count) -> Scroller.scrollBy "y", count * Settings.get("scrollStepSize"), 1, false
      "<c-y>": command: (count) -> Scroller.scrollBy "y", -count * Settings.get("scrollStepSize"), 1, false

    super extend options,
      name: options.name ? "visual"
      indicator: options.indicator ? "Visual mode"
      singleton: "visual-mode-group" # Visual mode, visual-line mode and caret mode each displace each other.
      exitOnEscape: true
      suppressAllKeyboardEvents: true
      keyMapping: keyMapping
      commandHandler: @commandHandler.bind this

    # If there was a range selection when the user lanuched visual mode, then we retain the selection on exit.
    @shouldRetainSelectionOnExit = @options.userLaunchedMode and DomUtils.getSelectionType(@selection) == "Range"

    @onExit (event = null) =>
      if @shouldRetainSelectionOnExit
        null # Retain any selection, regardless of how we exit.
      # This mimics vim: when leaving visual mode via Escape, collapse to focus, otherwise collapse to anchor.
      else if event?.type == "keydown" and KeyboardUtils.isEscape(event) and @name != "caret"
        @movement.collapseSelectionToFocus()
      else
        @movement.collapseSelectionToAnchor()
      # Don't leave the user in insert mode just because they happen to have selected an input.
      if document.activeElement and DomUtils.isEditable document.activeElement
        document.activeElement.blur() unless event?.type == "click"

    @push
      _name: "#{@id}/enter/click"
      # Yank on <Enter>.
      keypress: (event) =>
        if event.key == "Enter"
          unless event.metaKey or event.ctrlKey or event.altKey or event.shiftKey
            @yank()
            return @suppressEvent
        @continueBubbling
      # Click in a focusable element exits.
      click: (event) => @alwaysContinueBubbling =>
        @exit event if DomUtils.isFocusable event.target

    # Establish or use the initial selection.  If that's not possible, then enter caret mode.
    unless @name == "caret"
      if DomUtils.getSelectionType(@selection) in [ "Caret", "Range" ]
        selectionRect = @selection.getRangeAt(0).getBoundingClientRect()
        if window.vimiumDomTestsAreRunning
          # We're running the DOM tests, where getBoundingClientRect() isn't available.
          selectionRect ||= {top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0}
        selectionRect = Rect.intersect selectionRect, Rect.create 0, 0, window.innerWidth, window.innerHeight
        if selectionRect.height >= 0 and selectionRect.width >= 0
          # The selection is visible in the current viewport.
          if DomUtils.getSelectionType(@selection) == "Caret"
            # The caret is in the viewport. Make make it visible.
            @movement.extendByOneCharacter(forward) or @movement.extendByOneCharacter backward
        else
          # The selection is outside of the viewport: clear it.  We guess that the user has moved on, and is
          # more likely to be interested in visible content.
          @selection.removeAllRanges()

      if DomUtils.getSelectionType(@selection) != "Range" and @name != "caret"
        new CaretMode
        HUD.showForDuration "No usable selection, entering caret mode...", 2500

  commandHandler: ({command: {command}, count}) ->
    switch typeof command
      when "string"
        @movement.runMovement command for [0...count] by 1
      when "function"
        command count
    @movement.scrollIntoView()

  find: (count, backwards) =>
    initialRange = @selection.getRangeAt(0).cloneRange()
    for [0...count] by 1
      unless FindMode.execute null, {colorSelection: false, backwards}
        @movement.setSelectionRange initialRange
        HUD.showForDuration("No matches for '#{FindMode.query.rawQuery}'", 1000)
        return
    # The find was successfull. If we're in caret mode, then we should now have a selection, so we can
    # drop back into visual mode.
    new VisualMode if @name == "caret" and 0 < @selection.toString().length

  # Yank the selection; always exits; collapses the selection; set @yankedText and return it.
  yank: (args = {}) ->
    @yankedText = @selection.toString()
    @exit()
    HUD.copyToClipboard @yankedText

    message = @yankedText.replace /\s+/g, " "
    message = message[...12] + "..." if 15 < @yankedText.length
    plural = if @yankedText.length == 1 then "" else "s"
    HUD.showForDuration "Yanked #{@yankedText.length} character#{plural}: \"#{message}\".", 2500

    @yankedText

class VisualLineMode extends VisualMode
  constructor: (options = {}) ->
    super extend options, name: "visual/line", indicator: "Visual mode (line)"
    @extendSelection()

  commandHandler: (args...) ->
    super args...
    @extendSelection() if @modeIsActive

  extendSelection: ->
    initialDirection = @movement.getDirection()
    for direction in [ initialDirection, @movement.opposite[initialDirection] ]
      @movement.runMovement direction, lineboundary
      @movement.reverseSelection()

class CaretMode extends VisualMode
  constructor: (options = {}) ->
    super extend options, name: "caret", indicator: "Caret mode", alterMethod: "move"

    # Establish the initial caret.
    switch DomUtils.getSelectionType(@selection)
      when "None"
        @establishInitialSelectionAnchor()
        if DomUtils.getSelectionType(@selection) == "None"
          @exit()
          HUD.showForDuration "Create a selection before entering visual mode.", 2500
          return
      when "Range"
        @movement.collapseSelectionToAnchor()

    @movement.extendByOneCharacter forward
    @movement.scrollIntoView()

  commandHandler: (args...) ->
    @movement.collapseSelectionToAnchor()
    super args...
    @movement.extendByOneCharacter forward if @modeIsActive

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
          @movement.setSelectionRange range
          return true
    false

root = exports ? (window.root ?= {})
root.VisualMode = VisualMode
root.VisualLineMode = VisualLineMode
extend window, root unless exports?

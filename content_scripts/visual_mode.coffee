VisualMode =
  isSelectionForward: ->
    if ["INPUT", "TEXTAREA"].indexOf(document.activeElement.tagName) > -1
      document.activeElement.selectionDirection == "forward"
    else
      {anchorNode, anchorOffset, focusNode, focusOffset} = window.getSelection()

      (anchorPoint = new Range()).setStart anchorNode, anchorOffset
      (focusPoint = new Range()).setStart focusNode, focusOffset

      anchorPoint.compareBoundaryPoints(Range.START_TO_START, focusPoint) <= 0

  extendFront: (direction = "forward", granularity = "character") ->
    selectionForward = @isSelectionForward()
    @reverseSelection(selectionForward) unless selectionForward
    window.getSelection().modify "extend", direction, granularity
    @ensureNotEmpty direction

  extendBack: (direction = "forward", granularity = "character") ->
    selectionForward = @isSelectionForward()
    @reverseSelection(selectionForward) if selectionForward
    window.getSelection().modify "extend", direction, granularity
    @ensureNotEmpty direction

  extendFocus: (direction = "forward", granularity = "character") ->
    window.getSelection().modify "extend", direction, granularity

  extendAnchor: (direction = "forward", granularity = "character") ->
    @reverseSelection()
    @extendFocus direction, granularity
    @reverseSelection()
    @ensureNotEmpty direction

  # If we move the 'anchor' of the current selection so that it overlaps the 'focus', it takes 2 operations
  # to progress by one step.
  ensureNotEmpty: (direction = "forward") ->
    # There's already a cursor in input and textarea elements, so we don't have to ensure that there is a
    # selection.
    if ["INPUT", "TEXTAREA"].indexOf(document.activeElement.tagName) == -1
      selection = window.getSelection()
      selection.modify("extend", direction, "character") if selection.isCollapsed

  reverseSelection: (forward = @isSelectionForward())->
    if ["INPUT", "TEXTAREA"].indexOf(document.activeElement.tagName) > -1
      document.activeElement.selectionDirection = if forward then "backward" else "forward"
    else
      {anchorNode, anchorOffset, focusNode, focusOffset} = selection = window.getSelection()
      if forward
        selection.collapseToEnd()
      else
        selection.collapseToStart()
      selection.extend anchorNode, anchorOffset

directions = ["Forward", "Backward", "Left", "Right"]
granularities = [
  "Character", "Word", "Sentence", "Line", "Paragraph", "Lineboundary", "Sentenceboundary",
  "Paragraphboundary", "Documentboundary"
]
types = ["Front", "Back", "Focus", "Anchor"]

for direction in directions
  for granularity in granularities
    for type in types
      fnName = "extend#{type}#{direction}By#{granularity}"
      directionLower = direction.toLowerCase()
      granularityLower = granularity.toLowerCase()
      VisualMode[fnName] = VisualMode["extend#{type}"].bind(VisualMode, directionLower, granularityLower)

root = exports ? window
root.VisualMode = VisualMode

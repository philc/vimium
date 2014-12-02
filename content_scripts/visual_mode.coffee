VisualMode =
  isSelectionForwards: ->
    {anchorNode, anchorOffset, focusNode, focusOffset} = window.getSelection()

    (anchorPoint = new Range()).setStart anchorNode, anchorOffset
    (focusPoint = new Range()).setStart focusNode, focusOffset

    anchorPoint.compareBoundaryPoints(Range.START_TO_START, focusPoint) <= 0

  extendFront: (direction = "forward", granularity = "character") ->
    selectionForwards = @isSelectionForwards()
    @reverseSelection(selectionForwards) unless selectionForwards
    window.getSelection().modify "extend", direction, granularity

  extendBack: (direction = "forward", granularity = "character") ->
    selectionForwards = @isSelectionForwards()
    @reverseSelection(selectionForwards) if selectionForwards
    window.getSelection().modify "extend", direction, granularity

  extendFocus: (direction = "forward", granularity = "character") ->
    window.getSelection().modify "extend", direction, granularity

  extendAnchor: (direction = "forward", granularity = "character") ->
    @reverseSelection()
    @extendFocus direction, granularity
    @reverseSelection()

  reverseSelection: (forwards = @isSelectionForwards())->
    {anchorNode, anchorOffset, focusNode, focusOffset} = selection = window.getSelection()
    if forwards
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

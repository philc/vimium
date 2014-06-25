window.Scroller = root = {}

#
# activatedElement is different from document.activeElement -- the latter seems to be reserved mostly for
# input elements. This mechanism allows us to decide whether to scroll a div or to scroll the whole document.
#
activatedElement = null

# keep track of jump history, ie whenever `jumpTo()` is called.
jumpHistory = []
jumpPosition = 0

setActivatedElement = (el) ->
  activatedElement = el
  jumpHistory = []
  jumpPosition = 0

addToJumpHistory = (direction, val) ->
  point = {}
  if direction == 'x'
    point.x = val
    point.y = activatedElement[scrollProperties.y.axisName]
  else
    point.x = activatedElement[scrollProperties.x.axisName]
    point.y = val
  jumpHistory.push(point)


root.init = ->
  handlerStack.push DOMActivate: -> activatedElement = event.target

scrollProperties =
  x: {
    axisName: 'scrollLeft'
    max: 'scrollWidth'
    viewSize: 'clientHeight'
  }
  y: {
    axisName: 'scrollTop'
    max: 'scrollHeight'
    viewSize: 'clientWidth'
  }

getDimension = (el, direction, name) ->
  # the clientSizes of the body are the dimensions of the entire page, but the viewport should only be the
  # part visible through the window
  if name is 'viewSize' and el is document.body
    if direction is 'x' then window.innerWidth else window.innerHeight
  else
    el[scrollProperties[direction][name]]

# Chrome does not report scrollHeight accurately for nodes with pseudo-elements of height 0 (bug 110149).
# Therefore we cannot figure out if we have scrolled to the bottom of an element by testing if scrollTop +
# clientHeight == scrollHeight. So just try to increase scrollTop blindly -- if it fails we know we have
# reached the end of the content.
ensureScrollChange = (direction, changeFn) ->
  axisName = scrollProperties[direction].axisName
  element = activatedElement
  loop
    oldScrollValue = element[axisName]
    changeFn(element, axisName)
    newScrollValue = element[axisName]
    break unless (newScrollValue == oldScrollValue && element != document.body)
    lastElement = element
    # we may have an orphaned element. if so, just scroll the body element.
    element = element.parentElement || document.body

  # if the activated element has been scrolled completely offscreen, subsequent changes in its scroll
  # position will not provide any more visual feedback to the user. therefore we deactivate it so that
  # subsequent scrolls only move the parent element.
  rect = activatedElement.getBoundingClientRect()
  if (rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth)
    setActivatedElement(element)

  [oldScrollValue, newScrollValue]

# scroll the active element in :direction by :amount * :factor.
# :factor is needed because :amount can take on string values, which scrollBy converts to element dimensions.
root.scrollBy = (direction, amount, factor = 1) ->
  # if this is called before domReady, just use the window scroll function
  if (!document.body and amount instanceof Number)
    if (direction == "x")
      window.scrollBy(amount, 0)
    else
      window.scrollBy(0, amount)
    return

  if (!activatedElement || !isRendered(activatedElement))
    setActivatedElement(document.body)

  ensureScrollChange direction, (element, axisName) ->
    if Utils.isString amount
      elementAmount = getDimension element, direction, amount
    else
      elementAmount = amount
    elementAmount *= factor
    element[axisName] += elementAmount

root.scrollTo = (direction, pos, history, lastPosition) ->
  return unless document.body

  if (!activatedElement || !isRendered(activatedElement))
    setActivatedElement(document.body)

  [oldVal, newVal] = ensureScrollChange direction, (element, axisName) ->
    if Utils.isString pos
      elementPos = getDimension element, direction, pos
    else
      elementPos = pos
    element[axisName] = elementPos

  if history
    if lastPosition
      lastPosition[direction] = oldVal

  else if oldVal != newVal
    jumpHistory.length = jumpPosition
    lastPos = jumpHistory[jumpPosition] - 1
    if lastPos
      if lastPos[direction] != oldVal
        addToJumpHistory(direction, oldVal)
      else if lastPos[direction] != newVal
        addToJumpHistory(direction, newVal)
      jumpPosition++
    else
      addToJumpHistory(direction, oldVal)
      addToJumpHistory(direction, newVal)
      jumpPosition++


# TODO refactor and put this together with the code in getVisibleClientRect
isRendered = (element) ->
  computedStyle = window.getComputedStyle(element, null)
  return !(computedStyle.getPropertyValue("visibility") != "visible" ||
      computedStyle.getPropertyValue("display") == "none")

root.scrollBack = ->
  return unless document.body
  return unless activatedElement && isRendered(activatedElement)

  lastPosition = jumpHistory[jumpPosition]
  newPosition = jumpHistory[--jumpPosition]
  if newPosition
    root.scrollTo "x", newPosition.x, true, lastPosition
    root.scrollTo "y", newPosition.y, true, lastPosition
  else
    jumpPosition = 0

root.scrollForward = ->
  return unless document.body
  return unless activatedElement && isRendered(activatedElement)

  lastPosition = jumpHistory[jumpPosition]
  newPosition = jumpHistory[++jumpPosition]
  if newPosition
    root.scrollTo "x", newPosition.x, true, lastPosition
    root.scrollTo "y", newPosition.y, true, lastPosition
  else
    jumpPosition = jumpHistory.length - 1

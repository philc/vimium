window.Scroller = root = {}

#
# activatedElement is different from document.activeElement -- the latter seems to be reserved mostly for
# input elements. This mechanism allows us to decide whether to scroll a div or to scroll the whole document.
#
activatedElement = null
settings = null

root.init = (frontendSettings) ->
  settings = frontendSettings
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

getDimension = (el, direction, amount) ->
  if Utils.isString amount
    name = amount
    # the clientSizes of the body are the dimensions of the entire page, but the viewport should only be the
    # part visible through the window
    if name is 'viewSize' and el is document.body
      if direction is 'x' then window.innerWidth else window.innerHeight
    else
      el[scrollProperties[direction][name]]
  else
    amount

# Test whether element should be scrolled.
isScrollable = (element, direction) ->
  # Elements with `overflow: hidden` should not be scrolled.
  overflow = window.getComputedStyle(element).getPropertyValue("overflow-#{direction}")
  return false if overflow == "hidden"
  return true

# Chrome does not report scrollHeight accurately for nodes with pseudo-elements of height 0 (bug 110149).
# Therefore we cannot figure out if we have scrolled to the bottom of an element by testing if scrollTop +
# clientHeight == scrollHeight. So just try to increase scrollTop blindly -- if it fails we know we have
# reached the end of the content.
ensureScrollChange = (direction, changeFn) ->
  axisName = scrollProperties[direction].axisName
  element = activatedElement
  progress = 0
  loop
    oldScrollValue = element[axisName]
    changeFn(element, axisName) if isScrollable element, direction
    progress += element[axisName] - oldScrollValue
    break unless element[axisName] == oldScrollValue && element != document.body
    # we may have an orphaned element. if so, just scroll the body element.
    element = element.parentElement || document.body

  # if the activated element has been scrolled completely offscreen, subsequent changes in its scroll
  # position will not provide any more visual feedback to the user. therefore we deactivate it so that
  # subsequent scrolls only move the parent element.
  rect = activatedElement.getBoundingClientRect()
  if (rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth)
    activatedElement = element
  # Return the amount by which the scroll position has changed.
  return progress

# Scroll by a relative amount in some direction, possibly smoothly.
# The constants below seem to roughly match chrome's scroll speeds for both short and long scrolls.
# TODO(smblott) For very-long scrolls, chrome implements a soft landing; we don't.
doScrollBy = do ->
  interval = 10 # Update interval (in ms).
  duration = 120 # This must be a multiple of interval (also in ms).
  fudgeFactor = 25
  timer = null

  clearTimer = ->
    if timer
      clearInterval timer
      timer = null

  # Allow a bit longer for longer scrolls.
  calculateExtraDuration = (amount) ->
    extra = fudgeFactor * Math.log Math.abs amount
    # Ensure we have a multiple of interval.
    return interval * Math.round (extra / interval)

  scroller = (direction,amount) ->
    return ensureScrollChange direction, (element, axisName) -> element[axisName] += amount

  (direction,amount,wantSmooth) ->
    clearTimer()

    unless wantSmooth and settings.get "smoothScroll"
      scroller direction, amount
      return

    requiredTicks = (duration + calculateExtraDuration amount) / interval
    # Round away from 0, so that we don't leave any requested scroll amount unscrolled.
    rounder = (if 0 <= amount then Math.ceil else Math.floor)
    delta = rounder(amount / requiredTicks)

    ticks = 0
    ticker = ->
      # If we haven't scrolled by the expected amount, then we've hit the top, bottom or side of the activated
      # element, so stop scrolling.
      if scroller(direction, delta) != delta or ++ticks == requiredTicks
        clearTimer()

    timer = setInterval ticker, interval
    ticker()

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
    activatedElement = document.body

  elementAmount = getDimension activatedElement, direction, amount
  elementAmount *= factor

  doScrollBy direction, elementAmount, true

root.scrollTo = (direction, pos, wantSmooth=false) ->
  return unless document.body

  if (!activatedElement || !isRendered(activatedElement))
    activatedElement = document.body

  # Find the deepest scrollable element which would move if we scrolled it.  This is the element which
  # ensureScrollChange will scroll.
  # TODO(smblott) We're pretty much copying what ensureScrollChange does here.  Refactor.
  element = activatedElement
  axisName = scrollProperties[direction].axisName
  while element != document.body and
    (getDimension(element, direction, pos) == element[axisName] or not isScrollable element, direction)
      element = element.parentElement || document.body

  amount = getDimension(element,direction,pos) - element[axisName]
  doScrollBy direction, amount, wantSmooth

# TODO refactor and put this together with the code in getVisibleClientRect
isRendered = (element) ->
  computedStyle = window.getComputedStyle(element, null)
  return !(computedStyle.getPropertyValue("visibility") != "visible" ||
      computedStyle.getPropertyValue("display") == "none")

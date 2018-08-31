#
# activatedElement is different from document.activeElement -- the latter seems to be reserved mostly for
# input elements. This mechanism allows us to decide whether to scroll a div or to scroll the whole document.
#
activatedElement = null

# Previously, the main scrolling element was document.body.  If the "experimental web platform features" flag
# is enabled, then we need to use document.scrollingElement instead.  There's an explanation in #2168:
# https://github.com/philc/vimium/pull/2168#issuecomment-236488091

getScrollingElement = ->
  document.scrollingElement ? document.body

# Return 0, -1 or 1: the sign of the argument.
# NOTE(smblott; 2014/12/17) We would like to use Math.sign().  However, according to this site
# (https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Math/sign) Math.sign() was
# only introduced in Chrome 38.  This caused problems in R1.48 for users with old Chrome installations.  We
# can replace this with Math.sign() at some point.
getSign = (val) ->
  if not val
    0
  else
    if val < 0 then -1 else 1

scrollProperties =
  x: {
    axisName: 'scrollLeft'
    max: 'scrollWidth'
    viewSize: 'clientWidth'
  }
  y: {
    axisName: 'scrollTop'
    max: 'scrollHeight'
    viewSize: 'clientHeight'
  }

# Translate a scroll request into a number (which will be interpreted by `scrollBy` as a relative amount, or
# by `scrollTo` as an absolute amount).  :direction must be "x" or "y". :amount may be either a number (in
# which case it is simply returned) or a string.  If :amount is a string, then it is either "max" (meaning the
# height or width of element), or "viewSize".  In both cases, we look up and return the requested amount,
# either in `element` or in `window`, as appropriate.
getDimension = (el, direction, amount) ->
  if Utils.isString amount
    name = amount
    # the clientSizes of the body are the dimensions of the entire page, but the viewport should only be the
    # part visible through the window
    if name is 'viewSize' and el is getScrollingElement()
      # TODO(smblott) Should we not be returning the width/height of element, here?
      if direction is 'x' then window.innerWidth else window.innerHeight
    else
      el[scrollProperties[direction][name]]
  else
    amount

# Perform a scroll. Return true if we successfully scrolled by any amount, and false otherwise.
performScroll = (element, direction, amount) ->
  axisName = scrollProperties[direction].axisName
  before = element[axisName]
  element[axisName] += amount
  element[axisName] != before

# Test whether `element` should be scrolled. E.g. hidden elements should not be scrolled.
shouldScroll = (element, direction) ->
  computedStyle = window.getComputedStyle(element)
  # Elements with `overflow: hidden` must not be scrolled.
  return false if computedStyle.getPropertyValue("overflow-#{direction}") == "hidden"
  # Elements which are not visible should not be scrolled.
  return false if computedStyle.getPropertyValue("visibility") in ["hidden", "collapse"]
  return false if computedStyle.getPropertyValue("display") == "none"
  true

# Test whether element does actually scroll in the direction required when asked to do so.  Due to chrome bug
# 110149, scrollHeight and clientHeight cannot be used to reliably determine whether an element will scroll.
# Instead, we scroll the element by 1 or -1 and see if it moved (then put it back).  :factor is the factor by
# which :scrollBy and :scrollTo will later scale the scroll amount. :factor can be negative, so we need it
# here in order to decide whether we should test a forward scroll or a backward scroll.
# Bug last verified in Chrome 38.0.2125.104.
doesScroll = (element, direction, amount, factor) ->
  # amount is treated as a relative amount, which is correct for relative scrolls. For absolute scrolls (only
  # gg, G, and friends), amount can be either a string ("max" or "viewSize") or zero. In the former case,
  # we're definitely scrolling forwards, so any positive value will do for delta.  In the latter, we're
  # definitely scrolling backwards, so a delta of -1 will do.  For absolute scrolls, factor is always 1.
  delta = factor * getDimension(element, direction, amount) || -1
  delta = getSign delta # 1 or -1
  performScroll(element, direction, delta) and performScroll(element, direction, -delta)

isScrollableElement = (element, direction = "y", amount = 1, factor = 1) ->
  doesScroll(element, direction, amount, factor) and shouldScroll element, direction

# From element and its parents, find the first which we should scroll and which does scroll.
findScrollableElement = (element, direction, amount, factor) ->
  while element != getScrollingElement() and not isScrollableElement element, direction, amount, factor
    element = DomUtils.getContainingElement(element) ? getScrollingElement()
  element

# On some pages, the scrolling element is not actually scrollable.  Here, we search the document for the
# largest visible element which does scroll vertically. This is used to initialize activatedElement. See
# #1358.
firstScrollableElement = (element = null) ->
  unless element
    scrollingElement = getScrollingElement()
    if doesScroll(scrollingElement, "y", 1, 1) or doesScroll(scrollingElement, "y", -1, 1)
      return scrollingElement
    else
      element = document.body ? getScrollingElement()

  if doesScroll(element, "y", 1, 1) or doesScroll(element, "y", -1, 1)
    element
  else
    children = ({element: child, rect: DomUtils.getVisibleClientRect(child)} for child in element.children)
    children = children.filter (child) -> child.rect # Filter out non-visible elements.
    children.map (child) -> child.area = child.rect.width * child.rect.height
    for child in children.sort((a,b) -> b.area - a.area) # Largest to smallest by visible area.
      return ele if ele = firstScrollableElement child.element
    null

checkVisibility = (element) ->
  # If the activated element has been scrolled completely offscreen, then subsequent changes in its scroll
  # position will not provide any more visual feedback to the user. Therefore, we deactivate it so that
  # subsequent scrolls affect the parent element.
  rect = activatedElement.getBoundingClientRect()
  if (rect.bottom < 0 || rect.top > window.innerHeight || rect.right < 0 || rect.left > window.innerWidth)
    activatedElement = element

# How scrolling is handled by CoreScroller.
#   - For jump scrolling, the entire scroll happens immediately.
#   - For smooth scrolling with distinct key presses, a separate animator is initiated for each key press.
#     Therefore, several animators may be active at the same time.  This ensures that two quick taps on `j`
#     scroll to the same position as two slower taps.
#   - For smooth scrolling with keyboard repeat (continuous scrolling), the most recently-activated animator
#     continues scrolling at least until its keyup event is received.  We never initiate a new animator on
#     keyboard repeat.

# CoreScroller contains the core function (scroll) and logic for relative scrolls.  All scrolls are ultimately
# translated to relative scrolls.  CoreScroller is not exported.
CoreScroller =
  init: ->
    @time = 0
    @lastEvent = @keyIsDown = null
    @installCanceEventListener()

  # This installs listeners for events which should cancel smooth scrolling.
  installCanceEventListener: ->
    # NOTE(smblott) With extreme keyboard configurations, Chrome sometimes does not get a keyup event for
    # every keydown, in which case tapping "j" scrolls indefinitely.  This appears to be a Chrome/OS/XOrg bug
    # of some kind.  See #1549.
    handlerStack.push
      _name: 'scroller/track-key-status'
      keydown: (event) =>
        handlerStack.alwaysContinueBubbling =>
          @keyIsDown = true
          @time += 1 unless event.repeat
          @lastEvent = event
      keyup: (event) =>
        handlerStack.alwaysContinueBubbling =>
          @keyIsDown = false
          @time += 1
      blur: (event) =>
        handlerStack.alwaysContinueBubbling =>
          @time += 1 if event.target == window

  # Return true if CoreScroller would not initiate a new scroll right now.
  wouldNotInitiateScroll: -> @lastEvent?.repeat and Settings.get "smoothScroll"

  # Calibration fudge factors for continuous scrolling.  The calibration value starts at 1.0.  We then
  # increase it (until it exceeds @maxCalibration) if we guess that the scroll is too slow, or decrease it
  # (until it is less than @minCalibration) if we guess that the scroll is too fast.  The cutoff point for
  # which guess we make is @calibrationBoundary. We require: 0 < @minCalibration <= 1 <= @maxCalibration.
  minCalibration: 0.5 # Controls how much we're willing to slow scrolls down; smaller means more slow down.
  maxCalibration: 1.6 # Controls how much we're willing to speed scrolls up; bigger means more speed up.
  calibrationBoundary: 150 # Boundary between scrolls which are considered too slow, or too fast.

  # Scroll element by a relative amount (a number) in some direction.
  scroll: (element, direction, amount, continuous = true) ->
    return unless amount

    unless Settings.get "smoothScroll"
      # Jump scrolling.
      performScroll element, direction, amount
      checkVisibility element
      return

    # We don't activate new animators on keyboard repeats; rather, the most-recently activated animator
    # continues scrolling.
    return if @lastEvent?.repeat

    activationTime = ++@time
    myKeyIsStillDown = => @time == activationTime and @keyIsDown ? true

    # Store amount's sign and make amount positive; the arithmetic is clearer when amount is positive.
    sign = getSign amount
    amount = Math.abs amount

    # Initial intended scroll duration (in ms). We allow a bit longer for longer scrolls.
    duration = Math.max 100, 20 * Math.log amount

    totalDelta = 0
    totalElapsed = 0.0
    calibration = 1.0
    previousTimestamp = null
    cancelEventListener = @installCanceEventListener()

    animate = (timestamp) =>
      previousTimestamp ?= timestamp
      return requestAnimationFrame(animate) if timestamp == previousTimestamp

      # The elapsed time is typically about 16ms.
      elapsed = timestamp - previousTimestamp
      totalElapsed += elapsed
      previousTimestamp = timestamp

      # The constants in the duration calculation, above, are chosen to provide reasonable scroll speeds for
      # distinct keypresses.  For continuous scrolls, some scrolls are too slow, and others too fast. Here, we
      # speed up the slower scrolls, and slow down the faster scrolls.
      if myKeyIsStillDown() and 75 <= totalElapsed and @minCalibration <= calibration <= @maxCalibration
        calibration *= 1.05 if 1.05 * calibration * amount < @calibrationBoundary # Speed up slow scrolls.
        calibration *= 0.95 if @calibrationBoundary < 0.95 * calibration * amount # Slow down fast scrolls.

      # Calculate the initial delta, rounding up to ensure progress.  Then, adjust delta to account for the
      # current scroll state.
      delta = Math.ceil amount * (elapsed / duration) * calibration
      delta = if myKeyIsStillDown() then delta else Math.max 0, Math.min delta, amount - totalDelta

      if delta and performScroll element, direction, sign * delta
        totalDelta += delta
        requestAnimationFrame animate
      else
        # We're done.
        handlerStack.remove cancelEventListener
        checkVisibility element

    # If we've been asked not to be continuous, then we advance time, so the myKeyIsStillDown test always
    # fails.
    ++@time unless continuous

    # Start scrolling.
    requestAnimationFrame animate

# Scroller contains the two main scroll functions which are used by clients.
Scroller =
  init: ->
    handlerStack.push
      _name: 'scroller/active-element'
      DOMActivate: (event) -> handlerStack.alwaysContinueBubbling ->
        # If event.path is present, the true event taget (potentially inside a Shadow DOM inside
        # event.target) can be found as its first element.
        # NOTE(mrmr1993): event.path has been renamed to event.deepPath in the spec, but this change is not
        # yet implemented by Chrome.
        activatedElement = event.deepPath?[0] ? event.path?[0] ? event.target
    CoreScroller.init()

  # scroll the active element in :direction by :amount * :factor.
  # :factor is needed because :amount can take on string values, which scrollBy converts to element dimensions.
  scrollBy: (direction, amount, factor = 1, continuous = true) ->
    # if this is called before domReady, just use the window scroll function
    if (!getScrollingElement() and amount instanceof Number)
      if (direction == "x")
        window.scrollBy(amount, 0)
      else
        window.scrollBy(0, amount)
      return

    activatedElement ||= (getScrollingElement() and firstScrollableElement()) or getScrollingElement()
    return unless activatedElement

    # Avoid the expensive scroll calculation if it will not be used.  This reduces costs during smooth,
    # continuous scrolls, and is just an optimization.
    unless CoreScroller.wouldNotInitiateScroll()
      element = findScrollableElement activatedElement, direction, amount, factor
      elementAmount = factor * getDimension element, direction, amount
      CoreScroller.scroll element, direction, elementAmount, continuous

  scrollTo: (direction, pos) ->
    activatedElement ||= (getScrollingElement() and firstScrollableElement()) or getScrollingElement()
    return unless activatedElement

    element = findScrollableElement activatedElement, direction, pos, 1
    amount = getDimension(element,direction,pos) - element[scrollProperties[direction].axisName]
    CoreScroller.scroll element, direction, amount

  # Is element scrollable and not the activated element?
  isScrollableElement: (element) ->
    activatedElement ||= (getScrollingElement() and firstScrollableElement()) or getScrollingElement()
    element != activatedElement and isScrollableElement element

  # Scroll the top, bottom, left and right of element into view.  The is used by visual mode to ensure the
  # focus remains visible.
  scrollIntoView: (element) ->
    activatedElement ||= getScrollingElement() and firstScrollableElement()
    rect = element. getClientRects()?[0]
    if rect?
      # Scroll y axis.
      if rect.bottom < 0
        amount = rect.bottom - Math.min(rect.height, window.innerHeight)
        element = findScrollableElement element, "y", amount, 1
        CoreScroller.scroll element, "y", amount, false
      else if window.innerHeight < rect.top
        amount = rect.top + Math.min(rect.height - window.innerHeight, 0)
        element = findScrollableElement element, "y", amount, 1
        CoreScroller.scroll element, "y", amount, false

      # Scroll x axis.
      if rect.right < 0
        amount = rect.right - Math.min(rect.width, window.innerWidth)
        element = findScrollableElement element, "x", amount, 1
        CoreScroller.scroll element, "x", amount, false
      else if window.innerWidth < rect.left
        amount = rect.left + Math.min(rect.width - window.innerWidth, 0)
        element = findScrollableElement element, "x", amount, 1
        CoreScroller.scroll element, "x", amount, false

# Hack to make expanded tweets scrollable on Twitter (See #3045).
if DomUtils.isTopFrame() and window.location.host == "twitter.com"
  for method in ["scrollTo", "scrollBy"]
    do ->
      func = Scroller[method]
      Scroller[method] = ->
        element = document.querySelector "div.permalink-container div.permalink[role=main]"
        activatedElement = element ? getScrollingElement()
        func arguments...

if DomUtils.isTopFrame() and window.location.host in ["reddit.com", "new.reddit.com"]
  for method in ["scrollTo", "scrollBy"]
    do ->
      func = Scroller[method]
      Scroller[method] = ->
        element = document.getElementById "overlayScrollContainer"
        activatedElement = element ? getScrollingElement()
        func arguments...

root = exports ? (window.root ?= {})
root.Scroller = Scroller
extend window, root unless exports?

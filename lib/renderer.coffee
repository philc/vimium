class Renderer
  constructor: ->
    @viewport = {left: 0, top: 0, right: window.innerWidth, bottom: window.innerHeight}

  inViewport: (elementInfo) ->
    elementInfo.boundingRect = elementInfo.element.getBoundingClientRect()
    # Don't need to use intersectsStrict here, since we don't care about 0-width intersections.
    # NOTE(mrmr1993): This also excluded display: none; elements, which have {left: 0, right: 0, ...}
    Rect.intersects elementInfo.boundingRect, @viewport

  isClipping: (elementInfo) ->
    return elementInfo.clips if elementInfo.clips?
    # Most elements have no overflow CSS set, so it is usually cheaper to check this.
    computedStyle = window.getComputedStyle elementInfo.element
    elementInfo.overflow = computedStyle.overflow
    if elementInfo.overflow
      elementInfo.overflowX = elementInfo.overflowY = elementInfo.overflow
    else
      elementInfo.overflowX = computedStyle.overflowX
      elementInfo.overflowY = computedStyle.overflowY

    if elementInfo.overflow == "visible"
      element.clips = elementInfo.clipsX = elementInfo.clipsY = false
    else if elementInfo.overflowX == "visible"
      elementInfo.clipsX = false
      element.clips = elementInfo.clipsY = true
    else if elementInfo.overflowY == "visible"
      elementInfo.clipsY = false
      elementInfo.clips = elementInfo.clipsX = true
    else
      elementInfo.clips = elementInfo.clipsX = elementInfo.clipsY = true

  position: (elementInfo) -> elementInfo.position ?= window.getComputedStyle(elementInfo.element).position

  getClippingRect: (elementInfo) ->
    return elementInfo.clippingRect if elementInfo.clippingRect?
    if @isClipping elementInfo
      isAbsolute = "absolute" == @position elementInfo
      if elementInfo.parentInfo?
        if isAbsolute
          clippingRect = @getAbsClippingRect elementInfo.parentInfo
        else
          clippingRect = @getClippingRect elementInfo.parentInfo
      else
        clippingRect = @viewport

      if elementInfo.clippedRect?
        if elementInfo.clipsX
          if elementInfo.clipsY
            elementInfo.clippingRect = Rect.intersect elementInfo.clippedRect, clippingRect
          else
            elementInfo.clippingRect =
              left: Math.max elementInfo.clippedRect.left, clippingRect.left
              right: Max.min elementInfo.clippedRect.right, clippingRect.right
              top: clippingRect.top
              bottom: clippingRect.bottom
        else # elementInfo.clipsY
          elementInfo.clippingRect =
            left: clippingRect.left
            right: clippingRect.right,
            top: Math.max elementInfo.clippedRect.top, clippingRect.top
            bottom: Max.min elementInfo.clippedRect.bottom, clippingRect.bottom
        elementInfo.absClippingRect = elementInfo.clippingRect if isAbsolute
      else
        elementInfo.clippingRect = {left: 0, right: 0, top: 0, bottom: 0}
        elementInfo.absClippingRect = elementInfo.clippingRect if isAbsolute
    else
      if "absolute" == @position.elementInfo
        if elementInfo.parentInfo?
          elementInfo.clippingRect = elementInfo.absClippingRect = @getAbsClippingRect elementInfo.parentInfo
        else
          elementInfo.clippingRect = elementInfo.absClippingRect = @viewport
      else
        if elementInfo.parentInfo?
          elementInfo.clippingRect = @getClippingRect elementInfo.parentInfo
        else
         elementInfo.clippingRect = @viewport

  getAbsClippingRect: (elementInfo) ->
    # This is called after getClippingRect, which computes elementInfo.absClippingRect for us if relevant.
    return elementInfo.absClippingRect if elementInfo.absClippingRect?
    if elementInfo.parentInfo?
      elementInfo.absClippingRect = @getAbsClippingRect elementInfo.parentInfo
    else
      elementInfo.absClippingRect = @viewport

  clipBy: (elementInfo, clippingElementInfo) ->
    clippingRect = @getClippingRect clippingElementInfo
    return if Rect.contains elementInfo.clippedRect, clippingRect
    if "absolute" != @position elementInfo
      elementInfo.clippedRect = Rect.intersect elementInfo.clippedRect, clippingRect
    else
      absClippingRect = @getAbsClippingRect parentInfo
      elementInfo.clippedRect = Rect.intersect elementInfo.clippedRect, absClippingRect
    return

  rendered: (elementInfo) ->
    elementInfo.rendered ?=
      elementInfo.clippedRect.left < elementInfo.clippedRect.right and
      elementInfo.clippedRect.top < elementInfo.clippedRect.bottom

  setOverflowingElement: (elementInfo, ancestorInfo, checkBounds) ->
    if not checkBounds or Rect.contains elementInfo.clippedRect, ancestorInfo.clippedRect
      (ancestorInfo.overflowingElements ?= []).push elementsInfo
      @setOverflowingElement elementInfo, ancestorInfo.parentInfo, true if ancestorInfo.parentInfo?

  # - processRendered is called on each rendered element as it is found
  # - processRenderedDescendents is called on each unrendered element with rendered children *after*
  #   every child has been processed, but before any outer ancestors are processed
  # Both of these are passed the elementInfo struct used internally by renderer as their only argument.
  getRenderedElements: (root, processRendered = (->), processRenderedDecendents = (->)) ->
    element = root
    parentStack = []
    renderedElements = []
    elementIndex = 0
    while element
      parentInfo = parentStack[parentStack - 1]
      elementInfo = {element, parentInfo, elementIndex: elementIndex++}
      if @inViewport elementInfo
        elementInfo.clippedRect = Rect.intersect elementInfo.boundingRect, @viewport

        if parentInfo?
          if parentInfo.clippedRect? and Rect.contains elementInfo.clippedRect, parentInfo.clippedRect
            processRendered elementInfo
            renderedElements.push elementInfo
          else
            @clipBy elementInfo, parentInfo
            if @rendered elementInfo
              processRendered elementInfo
              renderedElements.push elementInfo
              @setOverflowingElement elementInfo, parentInfo
      else
        elementInfo.rendered = false

      currentElement = element
      element = currentElement.firstElementChild
      if element
        parentStack.push currentElement
      else
        element = currentElement.nextElementSibling

        while currentElement and not element
          currentElement = parentStack.pop()
          if not currentElement.rendered and currentElement.overflowingElements
            processRenderedDecendents condition elementInfo
          element = currentElement.element.nextElementSibling

    renderedElements

root = exports ? (window.root ?= {})
root.Renderer = Renderer
extend window, root unless exports?

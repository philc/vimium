DomUtils =
  #
  # Runs :callback if the DOM has loaded, otherwise runs it on load
  #
  documentReady: do ->
    loaded = false
    window.addEventListener("DOMContentLoaded", -> loaded = true)
    (callback) -> if loaded then callback() else window.addEventListener("DOMContentLoaded", callback)

  #
  # Adds a list of elements to a page.
  # Note that adding these nodes all at once (via the parent div) is significantly faster than one-by-one.
  #
  addElementList: (els, overlayOptions) ->
    parent = document.createElement("div")
    parent.id = overlayOptions.id if overlayOptions.id?
    parent.className = overlayOptions.className if overlayOptions.className?
    parent.appendChild(el) for el in els

    document.documentElement.appendChild(parent)
    parent

  #
  # Remove an element from its DOM tree.
  #
  removeElement: (el) -> el.parentNode.removeChild el

  #
  # Takes an array of XPath selectors, adds the necessary namespaces (currently only XHTML), and applies them
  # to the document root. The namespaceResolver in evaluateXPath should be kept in sync with the namespaces
  # here.
  #
  makeXPath: (elementArray) ->
    xpath = []
    for element in elementArray
      xpath.push(".//" + element, ".//xhtml:" + element)
    xpath.join(" | ")

  # Evaluates an XPath on the whole document, or on the contents of the fullscreen element if an element is
  # fullscreen.
  evaluateXPath: (xpath, resultType) ->
    contextNode =
      if document.webkitIsFullScreen then document.webkitFullscreenElement else document.documentElement
    namespaceResolver = (namespace) ->
      if (namespace == "xhtml") then "http://www.w3.org/1999/xhtml" else null
    document.evaluate(xpath, contextNode, namespaceResolver, resultType, null)

  #
  # Returns the first visible clientRect of an element if it exists. Otherwise it returns null.
  #
  getVisibleClientRect: (element) ->
    # Note: this call will be expensive if we modify the DOM in between calls.
    clientRects = (Rect.copy clientRect for clientRect in element.getClientRects())

    for clientRect in clientRects
      # If the link has zero dimensions, it may be wrapping visible
      # but floated elements. Check for this.
      if (clientRect.width == 0 || clientRect.height == 0)
        for child in element.children
          computedStyle = window.getComputedStyle(child, null)
          # Ignore child elements which are not floated and not absolutely positioned for parent elements with
          # zero width/height
          continue if (computedStyle.getPropertyValue('float') == 'none' &&
            computedStyle.getPropertyValue('position') != 'absolute')
          childClientRect = @getVisibleClientRect(child)
          continue if childClientRect == null or childClientRect.width < 3 or childClientRect.height < 3
          return childClientRect

      else
        clientRect = @cropRectToVisible clientRect

        continue if clientRect == null or clientRect.width < 3 or clientRect.height < 3

        # eliminate invisible elements (see test_harnesses/visibility_test.html)
        computedStyle = window.getComputedStyle(element, null)
        if (computedStyle.getPropertyValue('visibility') != 'visible' ||
            computedStyle.getPropertyValue('display') == 'none')
          continue

        return clientRect

    null

  #
  # Bounds the rect by the current viewport dimensions. If the rect is offscreen or has a height or width < 3
  # then null is returned instead of a rect.
  #
  cropRectToVisible: (rect) ->
    boundedRect = Rect.create(
      Math.max(rect.left, 0)
      Math.max(rect.top, 0)
      rect.right
      rect.bottom
    )
    if boundedRect.top >= window.innerHeight - 4 or boundedRect.left >= window.innerWidth - 4
      null
    else
      boundedRect

  #
  # Get the client rects for the <area> elements in a <map> based on the position of the <img> element using
  # the map. Returns an array of rects.
  #
  getClientRectsForAreas: (imgClientRect, areas) ->
    rects = []
    for area in areas
      coords = area.coords.split(",").map((coord) -> parseInt(coord, 10))
      shape = area.shape.toLowerCase()
      if shape in ["rect", "rectangle"] # "rectangle" is an IE non-standard.
        [x1, y1, x2, y2] = coords
      else if shape in ["circle", "circ"] # "circ" is an IE non-standard.
        [x, y, r] = coords
        diff = r / Math.sqrt 2 # Gives us an inner square
        x1 = x - diff
        x2 = x + diff
        y1 = y - diff
        y2 = y + diff
      else if shape == "default"
        [x1, y1, x2, y2] = [0, 0, imgClientRect.width, imgClientRect.height]
      else
        # Just consider the rectangle surrounding the first two points in a polygon. It's possible to do
        # something more sophisticated, but likely not worth the effort.
        [x1, y1, x2, y2] = coords

      rect = Rect.translate (Rect.create x1, y1, x2, y2), imgClientRect.left, imgClientRect.top
      rect = @cropRectToVisible rect

      rects.push {element: area, rect: rect} if rect and not isNaN rect.top
    rects

  #
  # Selectable means that we should use the simulateSelect method to activate the element instead of a click.
  #
  # The html5 input types that should use simulateSelect are:
  #   ["date", "datetime", "datetime-local", "email", "month", "number", "password", "range", "search",
  #    "tel", "text", "time", "url", "week"]
  # An unknown type will be treated the same as "text", in the same way that the browser does.
  #
  isSelectable: (element) ->
    unselectableTypes = ["button", "checkbox", "color", "file", "hidden", "image", "radio", "reset", "submit"]
    (element.nodeName.toLowerCase() == "input" && unselectableTypes.indexOf(element.type) == -1) ||
        element.nodeName.toLowerCase() == "textarea"

  simulateSelect: (element) ->
    element.focus()
    # When focusing a textbox, put the selection caret at the end of the textbox's contents.
    # For some HTML5 input types (eg. date) we can't position the caret, so we wrap this with a try.
    try element.setSelectionRange(element.value.length, element.value.length)

  simulateClick: (element, modifiers) ->
    modifiers ||= {}

    eventSequence = ["mouseover", "mousedown", "mouseup", "click"]
    for event in eventSequence
      mouseEvent = document.createEvent("MouseEvents")
      mouseEvent.initMouseEvent(event, true, true, window, 1, 0, 0, 0, 0, modifiers.ctrlKey, modifiers.altKey,
      modifiers.shiftKey, modifiers.metaKey, 0, null)
      # Debugging note: Firefox will not execute the element's default action if we dispatch this click event,
      # but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
      element.dispatchEvent(mouseEvent)

  # momentarily flash a rectangular border to give user some visual feedback
  flashRect: (rect) ->
    flashEl = document.createElement("div")
    flashEl.id = "vimiumFlash"
    flashEl.className = "vimiumReset"
    flashEl.style.left = rect.left + window.scrollX + "px"
    flashEl.style.top = rect.top  + window.scrollY  + "px"
    flashEl.style.width = rect.width + "px"
    flashEl.style.height = rect.height + "px"
    document.documentElement.appendChild(flashEl)
    setTimeout((-> DomUtils.removeElement flashEl), 400)

  suppressPropagation: (event) ->
    event.stopImmediatePropagation()

  suppressEvent: (event) ->
    event.preventDefault()
    @suppressPropagation(event)

  #
  # Returns true if the element is focusable. This includes embeds like Flash, which steal the keybaord focus.
  #
  isFocusable: (element) -> @isEditable(element) || @isEmbed(element)

  #
  # Embedded elements like Flash and quicktime players can obtain focus but cannot be programmatically
  # unfocused.
  #
  isEmbed: (element) -> ["embed", "object"].indexOf(element.nodeName.toLowerCase()) >= 0

  #
  # Input or text elements are considered focusable and able to receieve their own keyboard events,
  # and will enter enter mode if focused. Also note that the "contentEditable" attribute can be set on
  # any element which makes it a rich text editor, like the notes on jjot.com.
  #
  isEditable: (target) ->
    # Note: document.activeElement.isContentEditable is also rechecked in isInsertMode() dynamically.
    return true if target.isContentEditable
    nodeName = target.nodeName.toLowerCase()
    # use a blacklist instead of a whitelist because new form controls are still being implemented for html5
    noFocus = ["radio", "checkbox"]
    if (nodeName == "input" && noFocus.indexOf(target.type) == -1)
      return true
    focusableElements = ["textarea", "select"]
    focusableElements.indexOf(nodeName) >= 0

  isDescendant: (parent, child) ->
    node = child
    while (node != null)
      return true if (node == parent)
      node = node.parentNode
    false


root = exports ? window
root.DomUtils = DomUtils

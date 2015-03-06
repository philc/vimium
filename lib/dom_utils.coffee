DomUtils =
  #
  # Runs :callback if the DOM has loaded, otherwise runs it on load
  #
  documentReady: (func) ->
    if document.readyState == "loading"
      window.addEventListener "DOMContentLoaded", func
    else
      func()

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
        element.nodeName.toLowerCase() == "textarea" || element.isContentEditable

  # Input or text elements are considered focusable and able to receieve their own keyboard events, and will
  # enter insert mode if focused. Also note that the "contentEditable" attribute can be set on any element
  # which makes it a rich text editor, like the notes on jjot.com.
  isEditable: (element) ->
    return true if element.isContentEditable
    nodeName = element.nodeName?.toLowerCase()
    # Use a blacklist instead of a whitelist because new form controls are still being implemented for html5.
    if nodeName == "input" and element.type not in ["radio", "checkbox"]
      return true
    nodeName in ["textarea", "select"]

  # Embedded elements like Flash and quicktime players can obtain focus.
  isEmbed: (element) ->
    element.nodeName?.toLowerCase() in ["embed", "object"]

  isFocusable: (element) ->
    @isEditable(element) or @isEmbed element

  isDOMDescendant: (parent, child) ->
    node = child
    while (node != null)
      return true if (node == parent)
      node = node.parentNode
    false

  # True if element is editable and contains the active selection range.
  isSelected: (element) ->
    selection = document.getSelection()
    if element.isContentEditable
      node = selection.anchorNode
      node and @isDOMDescendant element, node
    else
      if selection.type == "Range" and selection.isCollapsed
	      # The selection is inside the Shadow DOM of a node. We can check the node it registers as being
	      # before, since this represents the node whose Shadow DOM it's inside.
        containerNode = selection.anchorNode.childNodes[selection.anchorOffset]
        element == containerNode # True if the selection is inside the Shadow DOM of our element.
      else
        false

  simulateSelect: (element) ->
    # If element is already active, then we don't move the selection.  However, we also won't get a new focus
    # event.  So, instead we pretend (to any active modes which care, e.g. PostFindMode) that element has been
    # clicked.
    if element == document.activeElement and DomUtils.isEditable document.activeElement
      handlerStack.bubbleEvent "click", target: element
    else
      element.focus()
      # If the cursor is at the start of the element's contents, send it to the end. Motivation:
      # * the end is a more useful place to focus than the start,
      # * this way preserves the last used position (except when it's at the beginning), so the user can
      #   'resume where they left off'.
      # NOTE(mrmr1993): Some elements throw an error when we try to access their selection properties, so
      # wrap this with a try.
      try
        if element.selectionStart == 0 and element.selectionEnd == 0
          element.setSelectionRange element.value.length, element.value.length



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

  # Suppress the next keyup event for Escape.
  suppressKeyupAfterEscape: (handlerStack) ->
    handlerStack.push
      _name: "dom_utils/suppressKeyupAfterEscape"
      keyup: (event) ->
        return true unless KeyboardUtils.isEscape event
        @remove()
        false

  simulateTextEntry: (element, text) ->
    event = document.createEvent "TextEvent"
    event.initTextEvent "textInput", true, true, null, text
    element.dispatchEvent event

  # Adapted from: http://roysharon.com/blog/37.
  # This finds the element containing the selection focus.
  getElementWithFocus: (selection, backwards) ->
    r = t = selection.getRangeAt 0
    if selection.type == "Range"
      r = t.cloneRange()
      r.collapse backwards
    t = r.startContainer
    t = t.childNodes[r.startOffset] if t.nodeType == 1
    o = t
    o = o.previousSibling while o and o.nodeType != 1
    t = o || t?.parentNode
    t

  # This calculates the caret coordinates within an input element.  It is used by edit mode to calculate the
  # caret position for scrolling.  It creates a hidden div contain a mirror of element, and all of the text
  # from element up to position, then calculates the scroll position.
  # From: https://github.com/component/textarea-caret-position/blob/master/index.js
  getCaretCoordinates: do ->
    # The properties that we copy to the mirrored div.
    properties = [
      'direction', 'boxSizing', 'width', 'height', 'overflowX', 'overflowY',
      'borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth',
      'paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft',
      'fontStyle', 'fontVariant', 'fontWeight', 'fontStretch', 'fontSize', 'fontSizeAdjust',
      'lineHeight', 'fontFamily',
      'textAlign', 'textTransform', 'textIndent', 'textDecoration',
      'letterSpacing', 'wordSpacing' ]

    (element, position) ->
      div = document.createElement "div"
      div.id = "vimium-input-textarea-caret-position-mirror-div"
      document.body.appendChild div

      style = div.style
      computed = getComputedStyle element

      style.whiteSpace = "pre-wrap"
      style.wordWrap = "break-word" if element.nodeName.toLowerCase() != "input"
      style.position = "absolute"
      style.visibility = "hidden"
      style[prop] = computed[prop] for prop in properties
      style.overflow = "hidden"

      div.textContent = element.value.substring 0, position
      if element.nodeName.toLowerCase() == "input"
        div.textContent = div.textContent.replace /\s/g, "\u00a0"

      span = document.createElement "span"
      span.textContent = element.value.substring(position) || "."
      div.appendChild span

      coordinates =
        top: span.offsetTop + parseInt computed["borderTopWidth"]
        left: span.offsetLeft + parseInt computed["borderLeftWidth"]

      document.body.removeChild div
      coordinates

  # Get the text content of an element (and its descendents), but omit the text content of previously-visited
  # nodes.  See #1514.
  # NOTE(smblott).  This is currently O(N^2) (when called on N elements).  An alternative would be to mark
  # each node visited, and then clear the marks when we're done.
  textContent: do ->
    visitedNodes = null
    reset: -> visitedNodes = []
    get: (element) ->
      nodes = document.createTreeWalker element, NodeFilter.SHOW_TEXT
      texts =
        while node = nodes.nextNode()
          continue unless node.nodeType == 3
          continue if node in visitedNodes
          text = node.data.trim()
          continue unless 0 < text.length
          visitedNodes.push node
          text
      texts.join " "

root = exports ? window
root.DomUtils = DomUtils

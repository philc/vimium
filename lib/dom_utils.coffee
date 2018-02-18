DomUtils =
  #
  # Runs :callback if the DOM has loaded, otherwise runs it on load
  #
  documentReady: do ->
    [isReady, callbacks] = [document.readyState != "loading", []]
    unless isReady
      window.addEventListener "DOMContentLoaded", onDOMContentLoaded = forTrusted ->
        window.removeEventListener "DOMContentLoaded", onDOMContentLoaded
        isReady = true
        callback() for callback in callbacks
        callbacks = null

    (callback) -> if isReady then callback() else callbacks.push callback

  documentComplete: do ->
    [isComplete, callbacks] = [document.readyState == "complete", []]
    unless isComplete
      window.addEventListener "load", onLoad = forTrusted ->
        window.removeEventListener "load", onLoad
        isComplete = true
        callback() for callback in callbacks
        callbacks = null

    (callback) -> if isComplete then callback() else callbacks.push callback

  createElement: (tagName) ->
    element = document.createElement tagName
    if element instanceof HTMLElement
      # The document namespace provides (X)HTML elements, so we can use them directly.
      @createElement = (tagName) -> document.createElement tagName
      element
    else
      # The document namespace doesn't give (X)HTML elements, so we create them with the correct namespace
      # manually.
      @createElement = (tagName) ->
        document.createElementNS "http://www.w3.org/1999/xhtml", tagName
      @createElement(tagName)

  #
  # Adds a list of elements to a page.
  # Note that adding these nodes all at once (via the parent div) is significantly faster than one-by-one.
  #
  addElementList: (els, overlayOptions) ->
    parent = @createElement "div"
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
  # Test whether the current frame is the top/main frame.
  #
  isTopFrame: ->
    window.top == window.self

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
  # WARNING: If testChildren = true then the rects of visible (eg. floated) children may be returned instead.
  # This is used for LinkHints and focusInput, **BUT IS UNSUITABLE FOR MOST OTHER PURPOSES**.
  #
  getVisibleClientRect: (element, testChildren = false) ->
    # Note: this call will be expensive if we modify the DOM in between calls.
    clientRects = (Rect.copy clientRect for clientRect in element.getClientRects())

    # Inline elements with font-size: 0px; will declare a height of zero, even if a child with non-zero
    # font-size contains text.
    isInlineZeroHeight = ->
      elementComputedStyle = window.getComputedStyle element, null
      isInlineZeroFontSize = (0 == elementComputedStyle.getPropertyValue("display").indexOf "inline") and
        (elementComputedStyle.getPropertyValue("font-size") == "0px")
      # Override the function to return this value for the rest of this context.
      isInlineZeroHeight = -> isInlineZeroFontSize
      isInlineZeroFontSize

    for clientRect in clientRects
      # If the link has zero dimensions, it may be wrapping visible but floated elements. Check for this.
      if (clientRect.width == 0 or clientRect.height == 0) and testChildren
        for child in element.children
          computedStyle = window.getComputedStyle(child, null)
          # Ignore child elements which are not floated and not absolutely positioned for parent elements
          # with zero width/height, as long as the case described at isInlineZeroHeight does not apply.
          # NOTE(mrmr1993): This ignores floated/absolutely positioned descendants nested within inline
          # children.
          continue if (computedStyle.getPropertyValue("float") == "none" and
            not (computedStyle.getPropertyValue("position") in ["absolute", "fixed"]) and
            not (clientRect.height == 0 and isInlineZeroHeight() and
              0 == computedStyle.getPropertyValue("display").indexOf "inline"))
          childClientRect = @getVisibleClientRect child, true
          continue if childClientRect == null or childClientRect.width < 3 or childClientRect.height < 3
          return childClientRect

      else
        clientRect = @cropRectToVisible clientRect

        continue if clientRect == null or clientRect.width < 3 or clientRect.height < 3

        # eliminate invisible elements (see test_harnesses/visibility_test.html)
        computedStyle = window.getComputedStyle(element, null)
        continue if computedStyle.getPropertyValue('visibility') != 'visible'

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
    return false unless element instanceof Element
    unselectableTypes = ["button", "checkbox", "color", "file", "hidden", "image", "radio", "reset", "submit"]
    (element.nodeName.toLowerCase() == "input" && unselectableTypes.indexOf(element.type) == -1) ||
        element.nodeName.toLowerCase() == "textarea" || element.isContentEditable

  # Input or text elements are considered focusable and able to receieve their own keyboard events, and will
  # enter insert mode if focused. Also note that the "contentEditable" attribute can be set on any element
  # which makes it a rich text editor, like the notes on jjot.com.
  isEditable: (element) ->
    (@isSelectable element) or element.nodeName?.toLowerCase() == "select"

  # Embedded elements like Flash and quicktime players can obtain focus.
  isEmbed: (element) ->
    element.nodeName?.toLowerCase() in ["embed", "object"]

  isFocusable: (element) ->
    element and (@isEditable(element) or @isEmbed element)

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
      if DomUtils.getSelectionType(selection) == "Range" and selection.isCollapsed
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
      if element.tagName.toLowerCase() != "textarea"
        # If the cursor is at the start of the (non-textarea) element's contents, send it to the end. Motivation:
        # * the end is a more useful place to focus than the start,
        # * this way preserves the last used position (except when it's at the beginning), so the user can
        #   'resume where they left off'.
        # NOTE(mrmr1993): Some elements throw an error when we try to access their selection properties, so
        # wrap this with a try.
        try
          if element.selectionStart == 0 and element.selectionEnd == 0
            element.setSelectionRange element.value.length, element.value.length

  simulateClick: (element, modifiers = {}) ->
    eventSequence = ["mouseover", "mousedown", "mouseup", "click"]
    for event in eventSequence
      defaultActionShouldTrigger =
        if Utils.isFirefox() and Object.keys(modifiers).length == 0 and event == "click" and
            element.target == "_blank" and element.href and
            not element.hasAttribute("onclick") and not element.hasAttribute("_vimium-has-onclick-listener")
          # Simulating a click on a target "_blank" element triggers the Firefox popup blocker.
          # Note(smblott) This will be incorrect if there is a click listener on the element.
          true
        else
          @simulateMouseEvent event, element, modifiers
      if event == "click" and defaultActionShouldTrigger and Utils.isFirefox()
        # Firefox doesn't (currently) trigger the default action for modified keys.
        if 0 < Object.keys(modifiers).length or element.target == "_blank"
          DomUtils.simulateClickDefaultAction element, modifiers
      defaultActionShouldTrigger # return the values returned by each @simulateMouseEvent call.

  simulateMouseEvent: do ->
    lastHoveredElement = undefined
    (event, element, modifiers = {}) ->

      if event == "mouseout"
        element ?= lastHoveredElement # Allow unhovering the last hovered element by passing undefined.
        lastHoveredElement = undefined
        return unless element?

      else if event == "mouseover"
        # Simulate moving the mouse off the previous element first, as if we were a real mouse.
        @simulateMouseEvent "mouseout", undefined, modifiers
        lastHoveredElement = element

      mouseEvent = document.createEvent("MouseEvents")
      mouseEvent.initMouseEvent(event, true, true, window, 1, 0, 0, 0, 0, modifiers.ctrlKey, modifiers.altKey,
      modifiers.shiftKey, modifiers.metaKey, 0, null)
      # Debugging note: Firefox will not execute the element's default action if we dispatch this click event,
      # but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
      element.dispatchEvent(mouseEvent)

  simulateClickDefaultAction: (element, modifiers = {}) ->
    return unless element.tagName?.toLowerCase() == "a" and element.href?

    {ctrlKey, shiftKey, metaKey, altKey} = modifiers

    # Mac uses a different new tab modifier (meta vs. ctrl).
    if KeyboardUtils.platform == "Mac"
      newTabModifier = metaKey == true and ctrlKey == false
    else
      newTabModifier = metaKey == false and ctrlKey == true

    if newTabModifier
      # Open in new tab. Shift determines whether the tab is focused when created. Alt is ignored.
      chrome.runtime.sendMessage {handler: "openUrlInNewTab", url: element.href, active:
        shiftKey == true}
    else if shiftKey == true and metaKey == false and ctrlKey == false and altKey == false
      # Open in new window.
      chrome.runtime.sendMessage {handler: "openUrlInNewWindow", url: element.href}
    else if element.target == "_blank"
      chrome.runtime.sendMessage {handler: "openUrlInNewTab", url: element.href, active: true}

    return

  addFlashRect: (rect) ->
    flashEl = @createElement "div"
    flashEl.classList.add "vimiumReset"
    flashEl.classList.add "vimiumFlash"
    flashEl.style.left = rect.left + "px"
    flashEl.style.top = rect.top + "px"
    flashEl.style.width = rect.width + "px"
    flashEl.style.height = rect.height + "px"
    document.documentElement.appendChild flashEl
    flashEl

  # momentarily flash a rectangular border to give user some visual feedback
  flashRect: (rect) ->
    flashEl = @addFlashRect rect
    setTimeout((-> DomUtils.removeElement flashEl), 400)

  getViewportTopLeft: ->
    box = document.documentElement
    style = getComputedStyle box
    rect = box.getBoundingClientRect()
    if style.position == "static" and not /content|paint|strict/.test(style.contain or "")
      # The margin is included in the client rect, so we need to subtract it back out.
      marginTop = parseInt style.marginTop
      marginLeft = parseInt style.marginLeft
      top: -rect.top + marginTop, left: -rect.left + marginLeft
    else
      if Utils.isFirefox()
        # These are always 0 for documentElement on Firefox, so we derive them from CSS border.
        clientTop = parseInt style.borderTopWidth
        clientLeft = parseInt style.borderLeftWidth
      else
        {clientTop, clientLeft} = box
      top: -rect.top - clientTop, left: -rect.left - clientLeft


  suppressPropagation: (event) ->
    event.stopImmediatePropagation()

  suppressEvent: (event) ->
    event.preventDefault()
    @suppressPropagation(event)

  consumeKeyup: do ->
    handlerId = null

    (event, callback = null, suppressPropagation) ->
      unless event.repeat
        handlerStack.remove handlerId if handlerId?
        code = event.code
        handlerId = handlerStack.push
          _name: "dom_utils/consumeKeyup"
          keyup: (event) ->
            return handlerStack.continueBubbling unless event.code == code
            @remove()
            if suppressPropagation
              DomUtils.suppressPropagation event
            else
              DomUtils.suppressEvent event
            handlerStack.continueBubbling
          # We cannot track keyup events if we lose the focus.
          blur: (event) ->
            @remove() if event.target == window
            handlerStack.continueBubbling
      callback?()
      if suppressPropagation
        DomUtils.suppressPropagation event
        handlerStack.suppressPropagation
      else
        DomUtils.suppressEvent event
        handlerStack.suppressEvent

  # Polyfill for selection.type (which is not available in Firefox).
  getSelectionType: (selection = document.getSelection()) ->
    selection.type or do ->
      if selection.rangeCount == 0
        "None"
      else if selection.isCollapsed
        "Caret"
      else
        "Range"

  # Adapted from: http://roysharon.com/blog/37.
  # This finds the element containing the selection focus.
  getElementWithFocus: (selection, backwards) ->
    r = t = selection.getRangeAt 0
    if DomUtils.getSelectionType(selection) == "Range"
      r = t.cloneRange()
      r.collapse backwards
    t = r.startContainer
    t = t.childNodes[r.startOffset] if t.nodeType == 1
    o = t
    o = o.previousSibling while o and o.nodeType != 1
    t = o || t?.parentNode
    t

  getSelectionFocusElement: ->
    sel = window.getSelection()
    if not sel.focusNode?
      null
    else if sel.focusNode == sel.anchorNode and sel.focusOffset == sel.anchorOffset
      # The selection either *is* an element, or is inside an opaque element (eg. <input>).
      sel.focusNode.childNodes[sel.focusOffset]
    else if sel.focusNode.nodeType != sel.focusNode.ELEMENT_NODE
      sel.focusNode.parentElement
    else
      sel.focusNode

  # Get the element in the DOM hierachy that contains `element`.
  # If the element is rendered in a shadow DOM via a <content> element, the <content> element will be
  # returned, so the shadow DOM is traversed rather than passed over.
  getContainingElement: (element) ->
    element.getDestinationInsertionPoints?()[0] or element.parentElement

  # This tests whether a window is too small to be useful.
  windowIsTooSmall: ->
    return window.innerWidth < 3 or window.innerHeight < 3

  # Inject user styles manually. This is only necessary for our chrome-extension:// pages and frames.
  injectUserCss: ->
    Settings.onLoaded ->
      style = document.createElement "style"
      style.type = "text/css"
      style.textContent = Settings.get "userDefinedLinkHintCss"
      document.head.appendChild style

root = exports ? (window.root ?= {})
root.DomUtils = DomUtils
extend window, root unless exports?

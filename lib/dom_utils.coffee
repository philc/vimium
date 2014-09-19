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
    for i of elementArray
      xpath.push("//" + elementArray[i], "//xhtml:" + elementArray[i])
    xpath.join(" | ")

  evaluateXPath: (xpath, resultType) ->
    namespaceResolver = (namespace) ->
      if (namespace == "xhtml") then "http://www.w3.org/1999/xhtml" else null
    document.evaluate(xpath, document.documentElement, namespaceResolver, resultType, null)

  #
  # Returns the first visible clientRect of an element if it exists. Otherwise it returns null.
  #
  getVisibleClientRect: (element) ->
    # Note: this call will be expensive if we modify the DOM in between calls.
    clientRects = ({
      top: clientRect.top, right: clientRect.right, bottom: clientRect.bottom, left: clientRect.left,
      width: clientRect.width, height: clientRect.height
    } for clientRect in element.getClientRects())

    for clientRect in clientRects
      if (clientRect.top < 0)
        clientRect.height += clientRect.top
        clientRect.top = 0

      if (clientRect.left < 0)
        clientRect.width += clientRect.left
        clientRect.left = 0

      if (clientRect.top >= window.innerHeight - 4 || clientRect.left  >= window.innerWidth - 4)
        continue

      if (clientRect.width < 3 || clientRect.height < 3)
        continue

      # eliminate invisible elements (see test_harnesses/visibility_test.html)
      computedStyle = window.getComputedStyle(element, null)
      if (computedStyle.getPropertyValue('visibility') != 'visible' ||
          computedStyle.getPropertyValue('display') == 'none' ||
          computedStyle.getPropertyValue('opacity') == '0')
        continue

      return clientRect

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
          continue if (childClientRect == null)
          return childClientRect
    null

  #
  # Selectable means the element has a text caret; this is not the same as "focusable".
  #
  isSelectable: (element) ->
    selectableTypes = ["search", "text", "password"]
    (element.nodeName.toLowerCase() == "input" && selectableTypes.indexOf(element.type) >= 0) ||
        element.nodeName.toLowerCase() == "textarea"

  simulateSelect: (element) ->
    element.focus()
    # When focusing a textbox, put the selection caret at the end of the textbox's contents.
    element.setSelectionRange(element.value.length, element.value.length)

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

  suppressEvent: (event) ->
    event.preventDefault()
    event.stopPropagation()

root = exports ? window
root.DomUtils = DomUtils

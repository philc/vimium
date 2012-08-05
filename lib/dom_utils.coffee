DomUtils =
  #
  # Runs :callback if the DOM has loaded, otherwise runs it on load
  #
  documentReady: (->
    loaded = false
    window.addEventListener("DOMContentLoaded", -> loaded = true)
    (callback) -> if loaded then callback() else window.addEventListener("DOMContentLoaded", callback)
  )()

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
    clientRects = element.getClientRects()
    clientRectsLength = clientRects.length

    for i in [0...clientRectsLength]
      if (clientRects[i].top < -2 || clientRects[i].top >= window.innerHeight - 4 ||
          clientRects[i].left < -2 || clientRects[i].left  >= window.innerWidth - 4)
        continue

      if (clientRects[i].width < 3 || clientRects[i].height < 3)
        continue

      # eliminate invisible elements (see test_harnesses/visibility_test.html)
      computedStyle = window.getComputedStyle(element, null)
      if (computedStyle.getPropertyValue('visibility') != 'visible' ||
          computedStyle.getPropertyValue('display') == 'none')
        continue

      return clientRects[i]

    for i in [0...clientRectsLength]
      # If the link has zero dimensions, it may be wrapping visible
      # but floated elements. Check for this.
      if (clientRects[i].width == 0 || clientRects[i].height == 0)
        childrenCount = element.children.length
        for j in [0...childrenCount]
          computedStyle = window.getComputedStyle(element.children[j], null)
          # Ignore child elements which are not floated and not absolutely positioned for parent elements with zero width/height
          if (computedStyle.getPropertyValue('float') == 'none' && computedStyle.getPropertyValue('position') != 'absolute')
            continue
          childClientRect = this.getVisibleClientRect(element.children[j])
          if (childClientRect == null)
            continue
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
      mouseEvent.initMouseEvent(event, true, true, window, 1, 0, 0, 0, 0, modifiers.ctrlKey, false, false,
          modifiers.metaKey, 0, null)
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
    document.body.appendChild(flashEl)
    setTimeout((-> flashEl.parentNode.removeChild(flashEl)), 400)

root = exports ? window
root.DomUtils = DomUtils

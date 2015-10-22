DomUtils.injectScript( -> # Hook addEventListener to tell link hints when a click listener is added.
  _addEventListener = EventTarget::addEventListener

  ElementRegistrar =
    elementsToRegister: []
    registrationElement: null

    init: ->
      # Create an element detatched from the DOM, register it with the content scripts.
      @registrationElement = document.createElementNS "http://www.w3.org/1999/xhtml", "div"
      registrationEvent = new CustomEvent "VimiumRegistrationElementEvent"
      document.documentElement.appendChild @registrationElement
      @registrationElement.dispatchEvent registrationEvent
      document.documentElement.removeChild @registrationElement

      for args in @elementsToRegister
        # Chrome stops us from using events to jump back and forth into extension code multiple times within
        # the same synchronous execution, so we execute these registration events asynchronously.
        do (args) -> setTimeout (=> @registerElementWithContentScripts.apply this, args), 0

      @elementsToRegister = null

    # Use custom events to pass the element to our content scripts as the event target. We do this in one of
    # two ways:
    #  * if the element is in the document, then the content script's event listener will capture the custom
    #    event as it bubbles through the document.
    #  * otherwise, the element is orphaned. Since we don't want to disrupt the DOM, we add its outermost
    #    parent (which must also be orphaned) to registrationElement instead, and the event bubbles to the
    #    content script's event listener on registrationElement.
    registerElementWithContentScripts: (element, type) ->
      unless @registrationElement?
        @elementsToRegister.push arguments
        return

      wrapInRegistrationElement = not document.contains element
      if wrapInRegistrationElement
        # The element isn't currently in the DOM. To avoid rendering it, firing MutationObservers, etc., we add
        # it to our registrationElement, which will capture the events without interfering with the DOM.
        elementToWrap = element
        elementToWrap = elementToWrap.parentElement while elementToWrap.parentElement?

        # If the element is in a shadow DOM, we would need a more complicated approach to pass it to the
        # content script. However, LinkHints doesn't check shadow DOMs for links, so we are safe to bail.
        return if elementToWrap.parentNode instanceof ShadowRoot

      @registrationElement.appendChild elementToWrap if wrapInRegistrationElement

      # Dispatch an event to the content scripts, where the event listener will mark the element.
      registrationEvent = new CustomEvent "VimiumRegistrationElementEvent-#{type}"
      element.dispatchEvent registrationEvent

      @registrationElement.removeChild elementToWrap if wrapInRegistrationElement

  EventTarget::addEventListener = (type, listener, useCapture) ->
    eventTarget = if this in [document, window] then document.documentElement else this
    if type == "click" and eventTarget instanceof Element
      setTimeout (-> ElementRegistrar.registerElementWithContentScripts eventTarget, "onclick"), 0
    _addEventListener.apply this, arguments

  # The registration event fails if sent before DOMContentLoaded (except when stepping through in developer
  # tools?!), so we wait to dispatch it.
  _addEventListener.call window, "DOMContentLoaded", (-> ElementRegistrar.init()), true
)

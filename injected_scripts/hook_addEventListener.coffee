DomUtils.injectScript( -> # Hook addEventListener to tell link hints when a click listener is added.

  _addEventListener = EventTarget::addEventListener # Store the original value of addEventListener.

  # Hook addEventListener to notify our content scripts of click listeners on elements.
  EventTarget::addEventListener = (type, listener, useCapture) ->
    # In order to show a link hint for click listeners on window/document, we associate them with
    # document.documentElement.
    eventTarget = if this in [document, window] then document.documentElement else this

    if type == "click" and eventTarget instanceof Element
      setTimeout (-> ElementRegistrar.registerElementWithContentScripts eventTarget, "onclick"), 0
    _addEventListener.apply this, arguments

  # The registration event fails if sent before DOMContentLoaded (except when stepping through in developer
  # tools?!), so we wait to dispatch it.
  _addEventListener.call window, "DOMContentLoaded", (-> ElementRegistrar.init()), true

  ElementRegistrar =
    elementsToRegister: []
    registrationElement: null

    init: ->
      # Create an element that we can use to capture events dispatched by elements not in the DOM from
      # content scripts.
      @registrationElement = document.createElementNS "http://www.w3.org/1999/xhtml", "div"
      registrationEvent = new CustomEvent "VimiumRegistrationElementEvent"

      # Add registrationElement to the document, dispatch an event for the content script's listener to
      # capture, and then remove registrationElement from the document again.
      # NOTE(mrmr1993): If this is run synchronously at document_start as intended, this shouldn't trigger
      # any page listeners, since page code hasn't run to register any yet.
      document.documentElement.appendChild @registrationElement
      @registrationElement.dispatchEvent registrationEvent
      document.documentElement.removeChild @registrationElement

      # Run queued registrations now that we are ready to handle them.
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
    #
    # NOTE(mrmr1993): Currently we don't support elements in shadow DOMs. This will need to be resolved (see
    # the TODO below) before we can fully resolve #1861.
    registerElementWithContentScripts: (element, type) ->
      unless @registrationElement?
        # |init| hasn't run yet, so we're not ready to handle this registration. Queue it to be run later.
        @elementsToRegister.push arguments
        return

      if document.contains element
        # The registration event will bubble to window, where the content script's listener will capture it.
        @sendRegistrationEvent element, type

      else
        # Find the outermost parent element of element, so that we're not disconnecting an element from its
        # current hierarchy with appendChild.
        elementToWrap = element
        elementToWrap = elementToWrap.parentElement while elementToWrap.parentElement?

        if elementToWrap.parentNode == null
          # The element isn't currently in the DOM. To avoid rendering it, firing MutationObservers, etc., we
          # add it briefly to our registrationElement, which will capture the events without interfering with
          # the DOM.
          @registrationElement.appendChild elementToWrap
          @sendRegistrationEvent element, type
          @registrationElement.removeChild elementToWrap
        else if elementToWrap.parentNode instanceof ShadowRoot
          # The element is in a shadow DOM. Currently LinkHints doesn't check shadow DOMs for links, so we
          # are safe to bail here.
          # TODO(mrmr1993): Eventually (ie. once Chromium 531990 is resolved), we should be able to use
          # event.deepPath to capture the element in the content script, and then the standard method should
          # work correctly. This wants to be resolved before #1861 can be.
          return
        else
          # elementToWrap is in a type of container node that we're not sure how to capture events from. Bail
          # for fear of causing more harm than good.
          return

    # Dispatch an event to the content scripts, where the event listener will mark the element.
    sendRegistrationEvent: (element, type) ->
      registrationEvent = new CustomEvent "VimiumRegistrationElementEvent-#{type}"
      element.dispatchEvent registrationEvent
)

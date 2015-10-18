_addEventListener = Element::addEventListener

loaded = false
elementsToRegister = []
registrationElement = null

EventTarget::addEventListener = (type, listener, useCapture) ->
  eventTarget = if this in [document, window] then document.documentElement else this
  if type == "click" and eventTarget instanceof Element
    setTimeout (-> registerElementWithContentScripts eventTarget, "onclick"), 0
  _addEventListener.apply this, arguments

onLoaded = ->
  loaded = true

  # Create an element detatched from the DOM, register it with the content scripts.
  registrationElement = document.createElementNS "http://www.w3.org/1999/xhtml", "div"
  registrationEvent = new CustomEvent "VimiumRegistrationElementEvent"
  document.documentElement.appendChild registrationElement
  registrationElement.dispatchEvent registrationEvent
  document.documentElement.removeChild registrationElement

  elementsToRegister.map (args) ->
    # Chrome stops us from using events to jump back and forth into extension code multiple times within the
    # same synchronous execution, so we execute these registration events asynchronously.
    setTimeout (-> registerElementWithContentScripts.apply null, args), 0

# The registration event fails if sent before DOMContentLoaded (except when stepping through in developer
# tools?!), so we wait to dispatch it.
_addEventListener.call window, "DOMContentLoaded", onLoaded, true

registerElementWithContentScripts = (element, type) ->
  unless loaded
    elementsToRegister.push arguments
    return

  wrapInRegistrationElement = not document.contains element
  if wrapInRegistrationElement
    # The element isn't currently in the DOM. To avoid rendering it, firing MutationObservers, etc., we add
    # it to our registrationElement, which will capture the events without interfering with the DOM.
    elementToWrap = element
    elementToWrap = elementToWrap.parentElement while elementToWrap.parentElement?
    registrationElement.appendChild elementToWrap

  # Dispatch an event to the content scripts, where the event listener will mark the element.
  registrationEvent = new CustomEvent "VimiumRegistrationElementEvent-#{type}"
  element.dispatchEvent registrationEvent

  registrationElement.removeChild elementToWrap if wrapInRegistrationElement

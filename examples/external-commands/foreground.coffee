hoverElement = null

Commands =
  sayHello:
    description: "Say hello."
    command: (options) ->
      alert "Hello!"

  hover:
    description: "Hover on an element selected via link hints."
    command: ({elementIndex}) ->
      hoverElement = document.documentElement.getElementsByTagName("*")[elementIndex]
      simulateMouseEvent "mouseover", hoverElement

  unhover:
    description: "Unhover on a previously-hovered element."
    command: ({elementIndex}) ->
      if hoverElement?
        simulateMouseEvent "mouseout", hoverElement
        hoverElement = null

if chrome?.extension?.getBackgroundPage?() != window
  #  This is a content window; add listener.
  window.addEventListener "message", (request) ->
    Commands[request.data?.name]?.command request.data

else
  # This is the background page; show some instructions.
  console.log "\n# Content-page commands:"
  for own name, command of Commands
    console.log "# #{command.description}\n  map X sendMessage name=#{name}"

simulateMouseEvent = do ->
  lastHoveredElement = undefined
  (event, element, modifiers = {}) ->

    if event == "mouseout"
      element ?= lastHoveredElement # Allow unhovering the last hovered element by passing undefined.
      lastHoveredElement = undefined
      return unless element?

    else if event == "mouseover"
      # Simulate moving the mouse off the previous element first, as if we were a real mouse.
      simulateMouseEvent "mouseout", undefined, modifiers
      lastHoveredElement = element

    mouseEvent = document.createEvent("MouseEvents")
    mouseEvent.initMouseEvent(event, true, true, window, 1, 0, 0, 0, 0, modifiers.ctrlKey, modifiers.altKey,
    modifiers.shiftKey, modifiers.metaKey, 0, null)
    # Debugging note: Firefox will not execute the element's default action if we dispatch this click event,
    # but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
    element.dispatchEvent(mouseEvent)


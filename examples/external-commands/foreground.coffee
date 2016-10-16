hoverElement = null

Commands =
  showAlert:
    description: "Pop up an alert."
    extra: "message=Hello!"
    command: (options) ->
      alert options.message ? "Hello!"

  hover:
    description: "Hover on an element selected via link hints."
    extra: "hint"
    command: ({elementIndex}) ->
      hoverElement = document.documentElement.getElementsByTagName("*")[elementIndex]
      DomUtils.simulateMouseEvent "mouseover", hoverElement

  unhover:
    description: "Unhover on a previously-hovered element."
    command: ({elementIndex}) ->
      if hoverElement?
        DomUtils.simulateMouseEvent "mouseout", hoverElement
        hoverElement = null

if chrome?.extension?.getBackgroundPage?() != window
  #  This is a content window; install listener.
  window.addEventListener "message", (request) ->
    Commands[request.data?.name]?.command request.data

# Utility for simulating mouse events.
DomUtils =
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

if chrome?.extension?.getBackgroundPage?() == window
  # This is the background page.  Store documentation in chrome.storage.local (for the options/help page).
  helpLines = []
  helpLines.push "# Content-page commands"
  for own name, command of Commands
    helpLines.push ""
    helpLines.push "# #{command.description}"
    helpLines.push "map X sendMessage name=#{name} #{command.extra ? ''}"

  helpLines.push ""
  chrome.storage.local.set "contentForeground": helpLines.join "\n"

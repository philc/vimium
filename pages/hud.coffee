findMode = null

document.addEventListener "keydown", (event) ->
  inputElement = document.getElementById "hud-find-input"
  return unless inputElement? # Don't do anything if we're not in find mode.
  transferrableEvent = {}
  for key, value of event
    transferrableEvent[key] = value if typeof value in ["number", "string"]

  if (event.keyCode in [keyCodes.backspace, keyCodes.deleteKey] and inputElement.textContent.length == 0) or
     event.keyCode == keyCodes.enter or KeyboardUtils.isEscape event

    DomUtils.suppressEvent event
    UIComponentServer.postMessage
      name: "hideFindMode"
      event: transferrableEvent
      query: findMode.rawQuery

  else if event.keyCode == keyCodes.upArrow
    if rawQuery = FindModeHistory.getQuery findMode.historyIndex + 1
      findMode.historyIndex += 1
      findMode.partialQuery = findMode.rawQuery if findMode.historyIndex == 0
      inputElement.textContent = rawQuery
      findMode.executeQuery()
  else if event.keyCode == keyCodes.downArrow
    findMode.historyIndex = Math.max -1, findMode.historyIndex - 1
    rawQuery = if 0 <= findMode.historyIndex then FindModeHistory.getQuery findMode.historyIndex else findMode.partialQuery
    inputElement.textContent = rawQuery
    findMode.executeQuery()

handlers =
  show: (data) ->
    document.getElementById("hud").innerText = data.text
    document.getElementById("hud").classList.add "vimiumUIComponentVisible"
    document.getElementById("hud").classList.remove "vimiumUIComponentHidden"
  hide: ->
    # We get a flicker when the HUD later becomes visible again (with new text) unless we reset its contents
    # here.
    document.getElementById("hud").innerText = ""
    document.getElementById("hud").classList.add "vimiumUIComponentHidden"
    document.getElementById("hud").classList.remove "vimiumUIComponentVisible"

  showFindMode: (data) ->
    hud = document.getElementById "hud"
    hud.innerText = "/"

    inputElement = document.createElement "span"
    inputElement.contentEditable = "plaintext-only"
    inputElement.textContent = data.text
    inputElement.id = "hud-find-input"
    hud.appendChild inputElement

    inputElement.addEventListener "input", executeQuery = (event) ->
      # Replace \u00A0 (&nbsp;) with a normal space.
      findMode.rawQuery = inputElement.textContent.replace "\u00A0", " "
      UIComponentServer.postMessage {name: "search", query: findMode.rawQuery}

    countElement = document.createElement "span"
    countElement.id = "hud-match-count"
    hud.appendChild countElement
    inputElement.focus()

    # Replace \u00A0 (&nbsp;) with a normal space.
    UIComponentServer.postMessage {name: "search", query: inputElement.textContent.replace "\u00A0", " "}

    findMode =
      historyIndex: -1
      partialQuery: ""
      rawQuery: ""
      executeQuery: executeQuery

  updateMatchesCount: ({matchCount, showMatchText}) ->
    countElement = document.getElementById "hud-match-count"
    return unless countElement? # Don't do anything if we're not in find mode.

    countText = if matchCount > 0
      " (#{matchCount} Match#{if matchCount == 1 then "" else "es"})"
    else
      " (No matches)"
    countElement.textContent = if showMatchText then countText else ""

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data

FindModeHistory.init()

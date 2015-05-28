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
    inputElement.textContent = data.text
    inputElement.id = "hud-find-input"
    hud.appendChild inputElement

    countElement = document.createElement "span"
    countElement.id = "hud-match-count"
    hud.appendChild countElement

    UIComponentServer.postMessage {name: "search", query: inputElement.textContent}

  updateMatchesCount: ({matchCount, showMatchText}) ->
    countElement = document.getElementById "hud-match-count"
    return unless countElement? # Don't do anything if we're not in find mode.

    plural = if matchCount == 1 then "" else "es"
    countText = if matchCount > 0
      " (" + matchCount + " Match#{plural})"
    else
      " (No matches)"
    countElement.textContent = if showMatchText then countText else ""

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data

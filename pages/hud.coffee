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
    inputElement.innerText = data.text
    inputElement.id = "hud-find-input"
    hud.appendChild inputElement

  updateMatchesCount: ({matchCount, showMatchText}) ->
    inputElement = document.getElementById "hud-find-input"
    return unless inputElement? # Don't do anything if we're not in find mode.
    nodeAfter = inputElement.nextSibling # The node containing the old match text.

    if showMatchText
      plural = if matchCount == 1 then "" else "es"
      countText = if matchCount > 0
        " (" + matchCount + " Match#{plural})"
      else
        " (No matches)"

      # Replace the old count (if there was one) with the new one.
      document.getElementById("hud").insertBefore document.createTextNode(countText), nodeAfter

    nodeAfter?.remove() # Remove the old match text.

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data

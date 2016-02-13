$ = (id) -> document.getElementById id

documentReady = (func) ->
  if document.readyState == "loading"
    window.addEventListener "DOMContentLoaded", handler = ->
      window.removeEventListener "DOMContentLoaded", handler
      func()
  else
    func()

documentReady ->
  html = []

  for own command, registryEntry of Commands
    html.push "<p><i># #{registryEntry.description}</i>:</br>"
    html.push "<tt><font size=3>map #{registryEntry.key || 'XX'} externalCommand #{chrome.runtime.id}.#{command}</font></tt></p>"

  $("exampleContainer").innerHTML = html.join ""

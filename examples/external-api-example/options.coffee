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

  for own command of Commands
    html.push "<p>#{Commands[command].description}:</br>"
    html.push "map XX externalCommand #{chrome.runtime.id}.#{command}</p>"

  $("exampleContainer").innerHTML = html.join ""

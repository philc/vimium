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

  for own group of Commands
    for own command of Commands[group]
      html.push "map XX externalCommand #{chrome.runtime.id}.#{command}<br/>"

  $("exampleContainer").innerHTML = html.join ""

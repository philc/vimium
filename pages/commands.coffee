window.addEventListener "DOMContentLoaded", (event) ->
  chrome.storage.local.get "helpPageData", ({helpPageData}) =>
    showTable helpPageData

# The ordering we show key bindings is alphanumerical, except that special keys sort to the end.
compareKeys = (a,b) ->
  a = a.replace "<","~"
  b = b.replace "<", "~"
  if a < b then -1 else if b < a then 1 else 0

window.showTable = (helpPageData) ->
  for own group, commands of helpPageData
    for command in commands
      commandSection = document.getElementsByClassName("command-#{command.command}")[0]
      keysSpan = commandSection.getElementsByClassName("keys")[0]

      keysSpan.innerHTML = ""
      keysSpan.appendChild document.createTextNode (command.keys.join ", ")

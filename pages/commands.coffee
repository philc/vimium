window.addEventListener "DOMContentLoaded", (event) ->
  chrome.storage.local.get "helpPageData", ({helpPageData}) =>
    showTable helpPageData

# The ordering we show key bindings is alphanumerical, except that special keys sort to the end.
compareKeys = (a,b) ->
  a = a.replace "<","~"
  b = b.replace "<", "~"
  if a < b then -1 else if b < a then 1 else 0

window.showTable = (helpPageData) ->
  article = document.getElementsByTagName("article")[0]
  article.innerHTML = ""
  for own group, commands of helpPageData
    groupSection = document.createElement "section"
    groupSection.className = "group-#{group}"

    groupHeader = document.createElement "h2"
    groupHeader.appendChild document.createTextNode group
    groupSection.appendChild groupHeader

    for command in commands
      commandSection = document.createElement "section"
      commandSection.className = "command-#{command.command}"
      commandHeader = document.createElement "h3"
      keysSpan = document.createElement "span"
      keysSpan.className = "keys"
      descriptionParagraph = document.createElement "p"
      descriptionParagraph.className = "description"

      commandHeader.appendChild document.createTextNode command.command + " "
      keysSpan.appendChild document.createTextNode (command.keys.join ", ")
      commandHeader.appendChild keysSpan
      descriptionParagraph.appendChild document.createTextNode command.description

      commandSection.appendChild commandHeader
      commandSection.appendChild descriptionParagraph

      groupSection.appendChild commandSection

    article.appendChild groupSection

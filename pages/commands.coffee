window.addEventListener "DOMContentLoaded", (event) ->
  chrome.storage.local.get "helpPageData", ({helpPageData}) =>
    showTable helpPageData

# The ordering we show key bindings is alphanumerical, except that special keys sort to the end.
compareKeys = (a,b) ->
  a = a.replace "<","~"
  b = b.replace "<", "~"
  if a < b then -1 else if b < a then 1 else 0

window.showTable = (helpPageData) ->
  table = document.getElementById "command-table"
  table.innerHTML = ""
  for own group, commands of helpPageData
    tbody = document.createElement "tbody"

    headerRow = document.createElement "tr"
    headerCell = document.createElement "th"
    headerCell.appendChild document.createTextNode group
    headerRow.appendChild headerCell
    tbody.appendChild headerRow

    for command in commands
      commandBody = document.createElement "tbody"
      commandRow = document.createElement "tr"
      commandCell = document.createElement "th"
      keysCell = document.createElement "td"

      commandCell.appendChild document.createTextNode command.command
      keysCell.appendChild document.createTextNode command.keys.join ", "

      commandRow.appendChild commandCell
      commandRow.appendChild keysCell
      commandBody.appendChild commandRow

      descriptionRow = document.createElement "tr"
      descriptionCell = document.createElement "td"
      descriptionCell.colspan = 2

      descriptionCell.appendChild document.createTextNode command.description

      descriptionRow.appendChild descriptionCell
      commandBody.appendChild descriptionRow

      tbody.appendChild commandBody

    table.appendChild tbody

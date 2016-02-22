$ = (id) -> document.getElementById id

document.addEventListener "DOMContentLoaded", ->
  $("vimiumVersion").innerText = Utils.getCurrentVersion()
  chrome.storage.local.get "installDate", (items) ->
    console.log new Date
    console.log items
    console.log items.installDate, items.installDate.toString()
    $("installDate").innerText = items.installDate.toString()


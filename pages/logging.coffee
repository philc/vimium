$ = (id) -> document.getElementById id

document.addEventListener "DOMContentLoaded", ->
  $("vimiumVersion").innerText = Utils.getCurrentVersion()
  chrome.storage.local.get "installDate", (items) ->
    $("installDate").innerText = items.installDate.toString()


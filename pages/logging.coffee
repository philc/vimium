$ = (id) -> document.getElementById id

document.addEventListener "DOMContentLoaded", ->
  $("vimiumVersion").innerText = Utils.getCurrentVersion()

  chrome.storage.local.get "installDate", (items) ->
    $("installDate").innerText = items.installDate.toString()

  branchRefRequest = new XMLHttpRequest()
  branchRefRequest.addEventListener "load", ->
    $("branchRef").innerText = branchRefRequest.responseText
    $("branchRef-wrapper").classList.add "no-hide"
  branchRefRequest.open "GET", chrome.extension.getURL ".git/HEAD"
  branchRefRequest.send()


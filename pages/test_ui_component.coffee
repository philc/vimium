UIComponentServer.addEventListener "message", (event) ->
  document.body.innerHTML = event.data

window.addEventListener "keydown", (event) ->
  if KeyboardUtils.isEscape event
    UIComponentServer.postMessage "hide"

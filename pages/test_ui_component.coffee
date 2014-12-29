UIComponentServer.addEventListener "message", (event) ->
  document.body.innerHTML = event.data

UIComponentServer.addEventListener "message", (event) ->
  document.body.innerHTML = event.data

document.addEventListener "DOMContentLoaded", ->
  document.addEventListener "keydown", (event) ->
    # Close on any key.
    console.log "How do I close myself?"

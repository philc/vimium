handlers =
  show: (data) ->
    document.getElementById("hud").innerText = data.text
    document.getElementById("hud").classList.add "vimiumUIComponentVisible"
    document.getElementById("hud").classList.remove "vimiumUIComponentHidden"
  hide: ->
    # We get a flicker when the HUD later becomes visible again (with new text) unless we reset its contents
    # here.
    document.getElementById("hud").innerText = ""
    document.getElementById("hud").classList.add "vimiumUIComponentHidden"
    document.getElementById("hud").classList.remove "vimiumUIComponentVisible"

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data

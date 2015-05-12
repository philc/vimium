handlers =
  show: (data) ->
    document.getElementById("hud").innerText = data.text
    document.getElementById("hud").classList.add "vimiumUIComponentVisible"
    document.getElementById("hud").classList.remove "vimiumUIComponentHidden"
  hide: ->
    document.getElementById("hud").classList.add "vimiumUIComponentHidden"
    document.getElementById("hud").classList.remove "vimiumUIComponentVisible"

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data

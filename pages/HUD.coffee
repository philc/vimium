showText = (data) ->
  document.getElementById("hud").innerText = data.text

showUpgradeNotification = (data) ->
  hud = document.getElementById "hud"
  hud.innerHTML = "Vimium has been upgraded to #{data.version}. See
    <a class='vimiumReset' target='_blank'
    href='https://github.com/philc/vimium#release-notes'>
    what's new</a>.<a class='vimiumReset close-button' href='#'>&times;</a>"

  links = hud.getElementsByTagName("a")
  links[0].addEventListener "click", updateLinkClicked, false
  links[1].addEventListener "click", (event) ->
    event.preventDefault()
    updateLinkClicked()
  , false

updateLinkClicked = ->
  UIComponentServer.postMessage name: "hideUpgradeNotification"
  chrome.runtime.sendMessage name: "upgradeNotificationClosed"

handlers =
  show: showText
  upgrade: showUpgradeNotification

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data

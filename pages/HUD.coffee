showText = (data) ->
  document.getElementById("hud").innerText = data.text

showUpgradeNotification = (data) ->
  hud = document.getElementById("hud")
  hud.innerHTML = "Vimium has been updated to <a class='vimiumReset'
    href='https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb'>
    #{data.version}</a>.<a class='vimiumReset close-button' href='#'>&times;</a>"

  links = hud.getElementsByTagName("a")
  links[0].addEventListener "click", (event) ->
    sendMessage name: "hideUpgradeNotification"
    chrome.runtime.sendMessage handler: "upgradeNotificationClosed"
  , false
  links[1].addEventListener "click", (event) ->
    event.preventDefault()
    sendMessage name: "hideUpgradeNotification"
    chrome.runtime.sendMessage handler: "upgradeNotificationClosed"
  , false

handlers = {
  show: showText
  update: showUpgradeNotification
}

handleMessage = (event) ->
  {data} = event
  handlers[data.name]? data

sendMessage = (data) ->
  window.parent.postMessage data, "*"

window.addEventListener "message", handleMessage, false

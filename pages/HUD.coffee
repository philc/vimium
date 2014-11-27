showText = (data) ->
  hud = document.getElementById "hud"
  hud.contentEditable = false
  hud.innerText = data.text

showUpgradeNotification = (data) ->
  hud = document.getElementById "hud"
  hud.contentEditable = false
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

enterFindMode = (data) ->
  hud = document.getElementById "hud"
  hud.innerText = "/"

  inputElement = document.createElement "span"
  inputElement.contentEditable = "plaintext-only"
  inputElement.id = "hud-find-input"
  hud.appendChild inputElement

  inputElement.addEventListener "input", (event) ->
    # Strip newlines in case the user had pasted some.
    sendMessage name: "search", query: inputElement.innerText.replace(/\r\n/g, "")
  inputElement.addEventListener "keydown", (event) ->
    eventType = undefined
    if KeyboardUtils.isEscape event
      eventType = "esc"
    else if (event.keyCode == keyCodes.backspace or event.keyCode == keyCodes.deleteKey)
      if inputElement.innerText.length == 0
        eventType = "del"
    else if event.keyCode == keyCodes.enter
      eventType = "enter"

    if eventType?
      DomUtils.suppressEvent event
      sendMessage name: "hideFindMode", type: eventType, query: inputElement.innerText.replace(/\r\n/g, "")
      inputElement.blur()

  inputElement.focus()

updateMatchesCount = (data) ->
  inputElement = document.getElementById "hud-find-input"
  return unless inputElement? # Don't do anything if we're not in find mode.

  hud = document.getElementById "hud"
  nodeAfter = inputElement.nextSibling
  countText = " (#{if data.count == 0 then "No" else data.count} matches)"

  # Replace the old count (if there was one) with the new one.
  hud.insertBefore document.createTextNode(countText), nodeAfter
  nodeAfter?.remove()


handlers = {
  show: showText
  update: showUpgradeNotification
  find: enterFindMode
  updateMatchesCount: updateMatchesCount
}

handleMessage = (event) ->
  {data} = event
  handlers[data.name]? data

sendMessage = (data) ->
  window.parent.postMessage data, "*"

window.addEventListener "message", handleMessage, false

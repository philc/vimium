showText = (data) ->
  hud = document.getElementById "hud"
  hud.innerText = data.text

showUpgradeNotification = (data) ->
  hud = document.getElementById "hud"
  hud.innerHTML = "Vimium has been upgraded to #{data.version}. See
    <a class='vimiumReset' target='_blank'
    href='https://github.com/philc/vimium#release-notes'>
    what's new</a>.<a class='vimiumReset close-button' href='#'>&times;</a>"

  updateLinkClicked = ->
    UIComponentServer.postMessage name: "hideUpgradeNotification"
    chrome.runtime.sendMessage name: "upgradeNotificationClosed"

  links = hud.getElementsByTagName("a")
  links[0].addEventListener "click", updateLinkClicked, false
  links[1].addEventListener "click", (event) ->
    event.preventDefault()
    updateLinkClicked()
  , false

enterFindMode = (data) ->
  hud = document.getElementById "hud"
  hud.innerText = "/"

  inputElement = document.createElement "span"
  inputElement.contentEditable = "plaintext-only"
  inputElement.id = "hud-find-input"
  hud.appendChild inputElement

  inputElement.addEventListener "input", (event) ->
    # Strip newlines in case the user has pasted some.
    UIComponentServer.postMessage name: "search", query: inputElement.innerText.replace(/\r\n/g, "")

  document.addEventListener "keydown", (event) ->
    if KeyboardUtils.isEscape event
      eventType = "esc"
    else if event.keyCode in [keyCodes.backspace, keyCodes.deleteKey]
      return unless inputElement.innerText.replace(/\r\n/g, "").length == 0
      eventType = "del"
    else if event.keyCode == keyCodes.enter
      eventType = "enter"
    else
      return true # Don't handle this key.

    DomUtils.suppressEvent event
    UIComponentServer.postMessage
      name: "hideFindMode"
      type: eventType
      query: inputElement.innerText.replace /\r\n/g, ""
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

handlers =
  show: showText
  upgrade: showUpgradeNotification
  find: enterFindMode
  updateMatchesCount: updateMatchesCount

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data

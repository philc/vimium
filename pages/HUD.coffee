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
  hud.innerHTML = ""
  hud.innerText = "/"

  inputElement = document.createElement "span"
  inputElement.contentEditable = "plaintext-only"
  inputElement.id = "hud-find-input"
  hud.appendChild inputElement

  getInputElementText = ->
    inputElement.innerText.replace /\r\n/g, ""

  updateSearch = (event, text = null) ->
    # Strip newlines in case the user has pasted some.
    UIComponentServer.postMessage name: "search", query: getInputElementText()

  setQueryAndUpdateSearch = (text) ->
    inputElement.innerText = ""
    DomUtils.simulateTextEntry inputElement, text
    updateSearch()

  inputElement.addEventListener "input", updateSearch
  inputElement.focus()

  FindModeHistory.init data.incognito
  historyIndex = -1
  partialQuery = ""

  onKeydown = (event) ->
    eventType = null

    # Find-mode history.
    if event.keyCode == keyCodes.upArrow
      if rawQuery = FindModeHistory.getQuery historyIndex + 1
        historyIndex += 1
        partialQuery = inputElement.innerText if historyIndex == 0
        setQueryAndUpdateSearch rawQuery
    else if event.keyCode == keyCodes.downArrow
      historyIndex = Math.max -1, historyIndex - 1
      rawQuery = if 0 <= historyIndex then FindModeHistory.getQuery historyIndex else partialQuery
      setQueryAndUpdateSearch rawQuery

    # Various ways of leaving find mode.
    else if KeyboardUtils.isEscape event
      eventType = "esc"
    else if event.keyCode in [keyCodes.backspace, keyCodes.deleteKey]
      return true unless getInputElementText().length == 0
      eventType = "del"
    else if event.keyCode == keyCodes.enter
      eventType = "enter"
      FindModeHistory.saveQuery getInputElementText()

    # Otherwise, don't handle this key.
    else return true

    DomUtils.suppressEvent event
    if eventType
      UIComponentServer.postMessage
        name: "hideFindMode"
        type: eventType
        query: getInputElementText()
      inputElement.blur()
      document.removeEventListener "keydown", onKeydown

  document.addEventListener "keydown", onKeydown

updateMatchesCount = ({ count: count, rawQuery: rawQuery }) ->
  inputElement = document.getElementById "hud-find-input"
  return unless inputElement? # Don't do anything if we're not in find mode.

  hud = document.getElementById "hud"
  nodeAfter = inputElement.nextSibling

  countText =
    if 0 < rawQuery.length
      plural = if count == 1 then "" else "es"
      count = if count == 0 then "No" else count
      " (#{count} match#{plural})"
    else
      ""

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

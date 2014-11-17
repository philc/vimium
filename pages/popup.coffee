
originalRule = undefined
originalPattern = undefined
originalPassKeys = undefined

generateDefaultPattern = (url) ->
  if /^https?:\/\/./.test url
    # The common use case is to disable Vimium at the domain level.
    # Generate "https?://www.example.com/*" from "http://www.example.com/path/to/page.html".
    "https?:/" + url.split("/",3)[1..].join("/") + "/*"
  else if /^[a-z]{3,}:\/\/./.test url
    # Anything else which seems to be a URL.
    url.split("/",3).join("/") + "/*"
  else
    url + "*"

reset = (initialize=false) ->
  document.getElementById("optionsLink").setAttribute "href", chrome.runtime.getURL("pages/options.html")
  chrome.tabs.getSelected null, (tab) ->
    isEnabled = chrome.extension.getBackgroundPage().isEnabledForUrl(url: tab.url)
    # Check if we have an existing exclusing rule for this page.
    if isEnabled.rule
      originalRule = isEnabled.rule
      originalPattern = originalRule.pattern
      originalPassKeys = originalRule.passKeys
    else
      originalRule = null
      originalPattern = generateDefaultPattern tab.url
      originalPassKeys = ""
    patternElement = document.getElementById("popupPattern")
    passKeysElement = document.getElementById("popupPassKeys")
    patternElement.value  = originalPattern
    passKeysElement.value = originalPassKeys
    if initialize
      # Activate <Ctrl-Enter> to save.
      for element in [ patternElement, passKeysElement ]
        element.addEventListener "keyup", (event) ->
          if event.ctrlKey and event.keyCode == 13
            addExclusionRule()
            window.close()
        element.addEventListener "focus", -> document.getElementById("helpText").style.display = "block"
        element.addEventListener "blur", -> document.getElementById("helpText").style.display = "none"
      # Focus passkeys with cursor at the end (but only when creating popup).
      passKeysElement.focus()
      passKeysElement.setSelectionRange(passKeysElement.value.length, passKeysElement.value.length)
    onChange()

onChange = ->
  # As the text in the popup's input elements is changed, update the the popup's buttons accordingly.
  # Aditionally, enable and disable those buttons as appropriate.
  pattern = document.getElementById("popupPattern").value.trim()
  passKeys = document.getElementById("popupPassKeys").value.trim()
  popupExclude = document.getElementById("popupExclude")

  document.getElementById("popupRemove").disabled =
    not (originalRule and pattern == originalPattern)

  if originalRule and pattern == originalPattern and passKeys == originalPassKeys
    popupExclude.disabled = true
    popupExclude.value = "Update Rule"

  else if originalRule and pattern == originalPattern
    popupExclude.disabled = false
    popupExclude.value = "Update Rule"

  else if originalRule
    popupExclude.disabled = false
    popupExclude.value = "Add Rule"

  else if pattern
    popupExclude.disabled = false
    popupExclude.value = "Add Rule"

  else
    popupExclude.disabled = true
    popupExclude.value = "Add Rule"

showMessage = do ->
  timer = null

  hideConfirmationMessage = ->
    document.getElementById("confirmationMessage").setAttribute "style", "display: none"
    timer = null

  (message) ->
    document.getElementById("confirmationMessage").setAttribute "style", "display: inline-block"
    document.getElementById("confirmationMessage").innerHTML = message
    clearTimeout(timer) if timer
    timer = setTimeout(hideConfirmationMessage,2000)

addExclusionRule = ->
  pattern = document.getElementById("popupPattern").value.trim()
  passKeys = document.getElementById("popupPassKeys").value.trim()
  chrome.extension.getBackgroundPage().addExclusionRule pattern, passKeys
  showMessage("Updated.")
  reset()

removeExclusionRule = ->
  pattern = document.getElementById("popupPattern").value.trim()
  chrome.extension.getBackgroundPage().removeExclusionRule pattern
  showMessage("Removed.")
  reset()

document.addEventListener "DOMContentLoaded", ->
  document.getElementById("popupExclude").addEventListener "click", addExclusionRule, false
  document.getElementById("popupRemove").addEventListener "click", removeExclusionRule, false
  for field in ["popupPattern", "popupPassKeys"]
    for event in ["input", "change"]
      document.getElementById(field).addEventListener event, onChange, false
  reset true

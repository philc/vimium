
originalRule = undefined
originalPattern = undefined
originalPassKeys = undefined

onLoad = ->
  document.getElementById("optionsLink").setAttribute "href", chrome.runtime.getURL("pages/options.html")
  chrome.tabs.getSelected null, (tab) ->
    isEnabled = chrome.extension.getBackgroundPage().isEnabledForUrl(url: tab.url)
    # Check if we have an existing exclusing rule for this page.
    if isEnabled.rule
      originalRule = isEnabled.rule
      originalPattern = originalRule.pattern
      originalPassKeys = originalRule.passKeys
    else
      # The common use case is to disable Vimium at the domain level.
      # This regexp will match "http://www.example.com/" from "http://www.example.com/path/to/page.html".
      domain = (tab.url.match(/[^\/]*\/\/[^\/]*\//) or tab.url) + "*"
      originalRule = null
      originalPattern = domain
      originalPassKeys = ""
    document.getElementById("popupPattern").value  = originalPattern
    document.getElementById("popupPassKeys").value = originalPassKeys
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
  onLoad()

removeExclusionRule = ->
  pattern = document.getElementById("popupPattern").value.trim()
  chrome.extension.getBackgroundPage().removeExclusionRule pattern
  showMessage("Removed.")
  onLoad()

document.addEventListener "DOMContentLoaded", ->
  document.getElementById("popupExclude").addEventListener "click", addExclusionRule, false
  document.getElementById("popupRemove").addEventListener "click", removeExclusionRule, false
  for field in ["popupPattern", "popupPassKeys"]
    for event in ["keyup", "change"]
      document.getElementById(field).addEventListener event, onChange, false
  onLoad()

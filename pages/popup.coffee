
originalRule = undefined
originalPattern = undefined
originalPassKeys = undefined

onLoad = ->
  document.getElementById("optionsLink").setAttribute "href", chrome.runtime.getURL("pages/options.html")
  chrome.tabs.getSelected null, (tab) ->
    isEnabled = chrome.extension.getBackgroundPage().isEnabledForUrl(url: tab.url)
    if isEnabled.rule
      # There is an existing exclusion rule for this page.
      originalRule = isEnabled.rule
      originalPattern = originalRule.pattern
      originalPassKeys = originalRule.passKeys
    else
      # There is not an existing exclusion rule.
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
  pattern = document.getElementById("popupPattern").value.trim()
  passKeys = document.getElementById("popupPassKeys").value.trim()

  document.getElementById("popupRemove").disabled =
    not (originalRule and pattern == originalPattern)

  if originalRule and pattern == originalPattern and passKeys == originalPassKeys
    document.getElementById("popupExclude").disabled = true
    document.getElementById("popupExclude").value = "Update Rule"

  else if originalRule and pattern == originalPattern
    document.getElementById("popupExclude").disabled = false
    document.getElementById("popupExclude").value = "Update Rule"

  else if originalRule
    document.getElementById("popupExclude").disabled = false
    document.getElementById("popupExclude").value = "Add Rule"

  else if pattern
    document.getElementById("popupExclude").disabled = false
    document.getElementById("popupExclude").value = "Add Rule"

  else
    document.getElementById("popupExclude").disabled = true
    document.getElementById("popupExclude").value = "Add Rule"

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

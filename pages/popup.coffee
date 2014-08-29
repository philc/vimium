onLoad = ->
  document.getElementById("optionsLink").setAttribute "href", chrome.runtime.getURL("pages/options.html")
  chrome.tabs.getSelected null, (tab) ->
    # Check if we have an existing exclusing rule for this page.
    isEnabled = chrome.extension.getBackgroundPage().isEnabledForUrl(url: tab.url)
    if isEnabled.rule
      # There is an existing rule for this page.
      document.getElementById("popupPattern").value  = isEnabled.rule.pattern
      document.getElementById("popupPassKeys").value = isEnabled.rule.passKeys
      document.getElementById("popupRemove").disabled = false
    else
      # No existing exclusion rule.
      # The common use case is to disable Vimium at the domain level.
      # This regexp will match "http://www.example.com/" from "http://www.example.com/path/to/page.html".
      domain = tab.url.match(/[^\/]*\/\/[^\/]*\//) or tab.url
      document.getElementById("popupPattern").value = domain + "*"
      document.getElementById("popupRemove").disabled = true

confirmTimer = null

hideConfirm = ->
  document.getElementById("confirmationMessage").setAttribute "style", "display: none"
  confirmTimer = null

addExclusionRule = ->
  pattern = document.getElementById("popupPattern").value
  passKeys = document.getElementById("popupPassKeys").value
  chrome.extension.getBackgroundPage().addExclusionRule pattern, passKeys
  document.getElementById("popupRemove").disabled = false
  document.getElementById("confirmationMessage").setAttribute "style", "display: inline-block"
  document.getElementById("confirmationMessage").innerHTML = "Saved."
  clearTimeout(confirmTimer) if confirmTimer
  confirmTimer = setTimeout(hideConfirm,2000)

removeExclusionRule = ->
  pattern = document.getElementById("popupPattern").value
  chrome.extension.getBackgroundPage().removeExclusionRule pattern
  document.getElementById("popupRemove").disabled = true
  document.getElementById("confirmationMessage").setAttribute "style", "display: inline-block"
  document.getElementById("confirmationMessage").innerHTML = "Removed."
  clearTimeout(confirmTimer) if confirmTimer
  confirmTimer = setTimeout(hideConfirm,2000)

document.addEventListener "DOMContentLoaded", ->
  document.getElementById("popupExclude").addEventListener "click", addExclusionRule, false
  document.getElementById("popupRemove").addEventListener "click", removeExclusionRule, false
  onLoad()

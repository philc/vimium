$ = (id) -> document.getElementById id

bgSettings = chrome.extension.getBackgroundPage().Settings

# "syncSettings" must appear FIRST in editableFields to ensure that, when it is
# changed, background_scripts/sync.coffee learns of that change before seeing
# any of the other settings' new values
editableFields = [ "syncSettings", "scrollStepSize", "excludedUrls", "linkHintCharacters",
  "userDefinedLinkHintCss", "keyMappings", "filterLinkHints", "previousPatterns",
  "nextPatterns", "hideHud", "regexFindMode", "searchUrl"]

canBeEmptyFields = ["excludedUrls", "keyMappings", "userDefinedLinkHintCss"]

# # dead code; refactored to ../background_scripts/settings.coffee(postUpdateHooks)
# postSaveHooks = keyMappings: (value) ->
#   commands = chrome.extension.getBackgroundPage().Commands
#   commands.clearKeyMappingsAndSetDefaults()
#   commands.parseCustomKeyMappings value
#   chrome.extension.getBackgroundPage().refreshCompletionKeysAfterMappingSave()

document.addEventListener "DOMContentLoaded", ->
  populateOptions()

  for field in editableFields
    $(field).addEventListener "keyup", onOptionKeyup, false
    $(field).addEventListener "change", enableSaveButton, false
    $(field).addEventListener "change", onDataLoaded, false

  $("advancedOptions").addEventListener "click", openAdvancedOptions, false
  $("showCommands").addEventListener "click", (->
    showHelpDialog chrome.extension.getBackgroundPage().helpDialogHtml(true, true, "Command Listing"), frameId
  ), false
  document.getElementById("restoreSettings").addEventListener "click", restoreToDefaults
  document.getElementById("saveOptions").addEventListener "click", saveOptions

window.onbeforeunload = -> "You have unsaved changes to options." unless $("saveOptions").disabled

onOptionKeyup = (event) ->
  if (event.target.getAttribute("type") isnt "checkbox" and
      event.target.getAttribute("savedValue") isnt event.target.value)
    enableSaveButton()

onDataLoaded = ->
  $("linkHintCharacters").readOnly = $("filterLinkHints").checked

enableSaveButton = ->
  $("saveOptions").removeAttribute "disabled"

# Saves options to localStorage.
saveOptions = ->

  # If the value is unchanged from the default, delete the preference from localStorage; this gives us
  # the freedom to change the defaults in the future.
  for fieldName in editableFields
    field = $(fieldName)
    if field.getAttribute("type") is "checkbox"
      fieldValue = field.checked
    else
      fieldValue = field.value.trim()
      field.value = fieldValue

    # If it's empty and not a field that we allow to be empty, restore to the default value
    if not fieldValue and canBeEmptyFields.indexOf(fieldName) is -1
      bgSettings.clear fieldName
      fieldValue = bgSettings.get(fieldName)
    else
      bgSettings.set fieldName, fieldValue
    $(fieldName).value = fieldValue
    $(fieldName).setAttribute "savedValue", fieldValue
    # # pre-refactoring of postSaveHooks to Settings.postUpdateHooks
    # postSaveHooks[fieldName] fieldValue if postSaveHooks[fieldName]
    chrome.extension.getBackgroundPage().Settings.doPostUpdateHooks fieldName, fieldValue

  $("saveOptions").disabled = true

# Restores select box state to saved value from localStorage.
populateOptions = ->
  for field in editableFields
    val = bgSettings.get(field) or ""
    setFieldValue $(field), val
  onDataLoaded()

restoreToDefaults = ->
  for field in editableFields
    val = bgSettings.defaults[field] or ""
    setFieldValue $(field), val
  onDataLoaded()
  enableSaveButton()

setFieldValue = (field, value) ->
  unless field.getAttribute("type") is "checkbox"
    field.value = value
    field.setAttribute "savedValue", value
  else
    field.checked = value

openAdvancedOptions = (event) ->
  elements = document.getElementsByClassName("advancedOption")
  for element in elements
    element.style.display = (if (element.style.display is "table-row") then "none" else "table-row")
  showOrHideLink = $("advancedOptions")
  if showOrHideLink.innerHTML.match(/^Show/)?
    showOrHideLink.innerHTML = "Hide advanced options&hellip;"
  else
    showOrHideLink.innerHTML = "Show advanced options&hellip;"
  event.preventDefault()

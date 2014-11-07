root = exports ? window

unless frameId?
  # The content scripts haven't initialized, so set this script to reload later, after they're done.
  root.page_scripts ?= {}
  page_scripts.js ?= []
  page_scripts.js.push chrome.extension.getURL("pages/help_dialog.js")
  return

{
  frameId: parentFrameId
  customTitle
  showCommandNames
} = Utils.getUrlOptions(document.location, {}, ["showCommandNames"])

VimiumHelpDialog =
  # This setting is pulled out of local storage. It's false by default.
  getShowAdvancedCommands: -> settings.get("helpDialog_showAdvancedCommands")

  init: ->
    this.dialogElement = document.getElementById("vimiumHelpDialog")
    this.dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].addEventListener("click",
      VimiumHelpDialog.toggleAdvancedCommands, false)

  showCommands: (groupsToCommands) ->
    for group, commands of groupsToCommands
      replaceElement = document.getElementById("replace_with_#{group}")
      replaceElement?.outerHTML = commands
    this.showAdvancedCommands(this.getShowAdvancedCommands())
    this.dialogElement.style.visibility = "visible"
    this.dialogElement.click() # Click the dialog element so that it is registered as the scrolling element.

  #
  # Advanced commands are hidden by default so they don't overwhelm new and casual users.
  #
  toggleAdvancedCommands: (event) ->
    event.preventDefault()
    showAdvanced = VimiumHelpDialog.getShowAdvancedCommands()
    VimiumHelpDialog.showAdvancedCommands(!showAdvanced)
    settings.set("helpDialog_showAdvancedCommands", !showAdvanced)

  showAdvancedCommands: (visible) ->
    VimiumHelpDialog.dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].innerHTML =
      if visible then "Hide advanced commands" else "Show advanced commands"
    advancedEls = VimiumHelpDialog.dialogElement.getElementsByClassName("advanced")
    for el in advancedEls
      el.style.display = if visible then "table-row" else "none"

  hide: ->
    # Communicate to our parent frame that our iframe should be removed.
    chrome.runtime.sendMessage
      handler: "echo"
      name: "toggleHelpDialog"
      frameId: parseInt(parentFrameId)


chrome.runtime.sendMessage
  handler: "getHelpDialogContents"
  frameId: frameId
  customTitle: customTitle
  showCommandNames: showCommandNames
, (response) -> VimiumHelpDialog.showCommands(response)

document.getElementsByClassName("closeButton")[0].addEventListener("click", ->
  VimiumHelpDialog.hide()
, false)
document.getElementsByClassName("optionsPage")[0].addEventListener("click", (clickEvent) ->
  clickEvent.preventDefault()
  chrome.runtime.sendMessage({handler: "openOptionsPageInNewTab"})
, false)
VimiumHelpDialog.init()

# Stub out help dialog commands and properties so we handle them correctly.
root.isShowingHelpDialog = true
root.showHelpDialog = ->
root.hideHelpDialog = -> VimiumHelpDialog.hide()

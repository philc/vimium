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
  stylesheet: null

  init: ->
    @dialogElement = document.getElementById("vimiumHelpDialog")
    @dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].addEventListener("click",
      VimiumHelpDialog.toggleAdvancedCommands, false)

    styleEl = document.createElement("style")
    styleEl.type = "text/css"
    styleEl.appendChild document.createTextNode("")
    document.head.appendChild(styleEl)

    @stylesheet = styleEl.sheet

  # Generates HTML for a given set of commands. commandLists are defined in commands.coffee
  populateFromCommandLists: ->
    document.getElementById("replace_with_title").outerHtml = customTitle or "Help"
    document.getElementById("replace_with_version").outerHtml = Utils.getCurrentVersion()
    for group, commandList of commandLists
      groupPlaceholder = document.getElementById("replace_with_#{group}")
      for command in commandList
        {name, description, advanced} = command

        commandRow = document.createElement "tr"
        commandRow.classList.add "vimiumReset", "commandRow", "command-#{name}"
        commandRow.classList.add "advanced" if advanced

        bindingsCell = document.createElement "td"
        bindingsCell.classList.add "vimiumReset", "bindings"
        commandRow.appendChild bindingsCell

        spacerCell = document.createElement "td"
        spacerCell.classList.add "vimiumReset"
        spacerCell.appendChild document.createTextNode ":"
        commandRow.appendChild spacerCell

        descriptionCell = document.createElement "td"
        descriptionCell.classList.add "vimiumReset"
        descriptionCell.appendChild document.createTextNode description
        commandRow.appendChild descriptionCell

        commandName = document.createElement "span"
        commandName.classList.add "vimiumReset", "commandName"
        commandName.appendChild document.createTextNode " (#{name})"
        descriptionCell.appendChild commandName

        groupPlaceholder.parentElement.insertBefore commandRow, groupPlaceholder
      groupPlaceholder.remove()
    if showCommandNames
      @stylesheet.insertRule("span.vimiumReset.commandName {display: inline;}", 0)
      @stylesheet.insertRule("tr.vimiumReset.commandRow {display: table-row;}", 1)
    @dialogElement.style.visibility = "visible"
    @dialogElement.click() # Click the dialog element so that it is registered as the scrolling element.

  updateWithBindings: (keyToCommandRegistry) ->
    for key, {name} of keyToCommandRegistry
      commandRow = document.getElementsByClassName("command-#{name}")[0]
      commandRow.style.display = "table-row"

      bindingsCell = commandRow.getElementsByClassName("bindings")[0]
      seperator = if bindingsCell.firstChild != null then ", " else ""
      bindingsCell.appendChild document.createTextNode(seperator + key)
    @dialogElement.click() # Click the dialog element so that it is registered as the scrolling element.

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


document.getElementsByClassName("closeButton")[0].addEventListener("click", ->
  VimiumHelpDialog.hide()
, false)
document.getElementsByClassName("optionsPage")[0].addEventListener("click", (clickEvent) ->
  clickEvent.preventDefault()
  chrome.runtime.sendMessage({handler: "openOptionsPageInNewTab"})
, false)

VimiumHelpDialog.init()
VimiumHelpDialog.populateFromCommandLists()
chrome.runtime.sendMessage
  handler: "getKeyToCommandRegistry"
  frameId: frameId
, (response) -> VimiumHelpDialog.updateWithBindings(response)

# Stub out help dialog commands and properties so we handle them correctly.
root.isShowingHelpDialog = true
root.showHelpDialog = ->
root.hideHelpDialog = -> VimiumHelpDialog.hide()

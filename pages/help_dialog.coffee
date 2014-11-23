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
  commandToRow: {}

  init: ->
    @dialogElement = document.getElementById("vimiumHelpDialog")
    @dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].addEventListener("click", ->
      VimiumHelpDialog.toggleAdvancedCommands(event)
    , false)

    styleEl = document.createElement("style")
    styleEl.type = "text/css"
    styleEl.appendChild document.createTextNode("")
    document.head.appendChild(styleEl)

    @stylesheet = styleEl.sheet

    advancedCssEl = document.createElement("style")
    advancedCssEl.type = "text/css"
    document.head.appendChild(advancedCssEl)

    # This stylesheet hides all advanced commands.
    @hideAdvancedStyle = advancedCssEl.sheet
    @hideAdvancedStyle.insertRule("span.showAdvanced { display: inline; }", 0)
    @hideAdvancedStyle.insertRule("span.hideAdvanced { display: none; }", 1)
    @hideAdvancedStyle.insertRule("tr.vimiumReset.commandRow.advanced { display: none !important; }", 2)
    @hideAdvancedStyle.disabled = false

  # Generates HTML for a given set of commands. commandLists are defined in commands.coffee
  populateFromCommandLists: ->
    document.getElementById("replace_with_title").outerHtml = customTitle or "Help"
    document.getElementById("replace_with_version").outerHtml = Utils.getCurrentVersion()
    columnContainer = document.getElementById("columnContainer")

    sectionTemplate = document.getElementById("sectionTemplate").content
    commandRowTemplate = document.getElementById("commandRowTemplate").content

    for group, commandList of commandLists
      groupContainer = document.importNode(sectionTemplate, true)
      sectionTitle = groupContainer.querySelector("td.vimiumHelpSectionTitle")
      sectionTitle.appendChild(document.createTextNode(groupDescriptions[group]))
      groupTable = groupContainer.querySelector("tbody")

      for command in commandList
        {name, description, advanced} = command

        commandRow = document.importNode(commandRowTemplate, true)
        trElement = @commandToRow[name] = commandRow.querySelector("tr")

        trElement.classList.add("advanced") if advanced

        descriptionCell = commandRow.querySelector("td.commandDescription")
        descriptionCell.insertBefore(document.createTextNode(description), descriptionCell.firstChild)

        commandName = commandRow.querySelector("span.commandName")
        commandName.appendChild(document.createTextNode(" (#{name})"))

        groupTable.appendChild(commandRow)
      columnContainer.appendChild(groupContainer)

    if showCommandNames
      @stylesheet.insertRule("span.vimiumReset.commandName {display: inline;}", 0)
      @stylesheet.insertRule("tr.vimiumReset.commandRow.unmappedCommand {display: table-row;}", 1)
    @showAdvancedCommands(@getShowAdvancedCommands())
    settings.addEventListener("load", =>
      @showAdvancedCommands(@getShowAdvancedCommands()))
    @dialogElement.style.visibility = "visible"
    @dialogElement.click() # Click the dialog element so that it is registered as the scrolling element.

  updateWithBindings: (keyToCommandRegistry) ->
    commandToKeyRegistry = {}
    for key, {name} of keyToCommandRegistry
      commandToKeyRegistry[name] ?= []
      commandToKeyRegistry[name].push(key)

    for name, keys of commandToKeyRegistry
      commandRow = @commandToRow[name]
      commandRow.classList.remove("unmappedCommand")

      bindingsCell = commandRow.querySelector("td.commandBindings")
      bindingsCell.appendChild(document.createTextNode(commandToKeyRegistry[name].join(", ")))
    @alignColumns()
    @dialogElement.click() # Click the dialog element so that it is registered as the scrolling element.

  # CSS hack to line up the command column across multiple tables.
  alignColumns: ->
    maxWidth = 0
    tables = document.querySelectorAll("table")
    for table in tables
      firstCell = table.querySelector("td.commandBindings")
      maxWidth = Math.max(maxWidth, firstCell.scrollWidth)

    for name, commandRow of @commandToRow
      firstCell = commandRow.querySelector("td")
      firstCell.style.width = maxWidth + "px"

  #
  # Advanced commands are hidden by default so they don't overwhelm new and casual users.
  #
  toggleAdvancedCommands: (event) ->
    event.preventDefault()
    showAdvanced = @getShowAdvancedCommands()
    @showAdvancedCommands(!showAdvanced)
    settings.set("helpDialog_showAdvancedCommands", !showAdvanced)

  showAdvancedCommands: (visible) -> @hideAdvancedStyle.disabled = visible

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

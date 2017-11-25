$ = (id) -> document.getElementById id
$$ = (element, selector) -> element.querySelector selector

# The ordering we show key bindings is alphanumerical, except that special keys sort to the end.
compareKeys = (a,b) ->
  a = a.replace "<","~"
  b = b.replace "<", "~"
  if a < b then -1 else if b < a then 1 else 0

# This overrides the HelpDialog implementation in vimium_frontend.coffee.  We provide aliases for the two
# HelpDialog methods required by normalMode (isShowing() and toggle()).
HelpDialog =
  dialogElement: null
  isShowing: -> true

  # This setting is pulled out of local storage. It's false by default.
  getShowAdvancedCommands: -> Settings.get("helpDialog_showAdvancedCommands")

  init: ->
    return if @dialogElement?
    @dialogElement = document.getElementById "vimiumHelpDialog"

    @dialogElement.getElementsByClassName("closeButton")[0].addEventListener("click", (clickEvent) =>
        clickEvent.preventDefault()
        @hide()
      false)
    document.getElementById("helpDialogOptionsPage").addEventListener("click", (clickEvent) ->
        clickEvent.preventDefault()
        chrome.runtime.sendMessage({handler: "openOptionsPageInNewTab"})
      false)
    document.getElementById("toggleAdvancedCommands").addEventListener("click",
      HelpDialog.toggleAdvancedCommands.bind(HelpDialog), false)

    document.documentElement.addEventListener "click", (event) =>
      @hide() unless @dialogElement.contains event.target
    , false

  instantiateHtmlTemplate: (parentNode, templateId, callback) ->
    templateContent = document.querySelector(templateId).content
    node = document.importNode templateContent, true
    parentNode.appendChild node
    callback parentNode.lastElementChild

  show: ({showAllCommandDetails}) ->
    $("help-dialog-title").textContent = if showAllCommandDetails then "Command Listing" else "Help"
    $("help-dialog-version").textContent = Utils.getCurrentVersion()

    chrome.storage.local.get "helpPageData", ({helpPageData}) =>
      for own group, commands of helpPageData
        container = @dialogElement.querySelector("#help-dialog-#{group}")
        container.innerHTML = ""
        for command in commands when showAllCommandDetails or 0 < command.keys.length
          keysElement = null
          descriptionElement = null

          useTwoRows = 12 <= command.keys.join(", ").length
          unless useTwoRows
            @instantiateHtmlTemplate container, "#helpDialogEntry", (element) ->
              element.classList.add "advanced" if command.advanced
              keysElement = descriptionElement = element
          else
            @instantiateHtmlTemplate container, "#helpDialogEntryBindingsOnly", (element) ->
              element.classList.add "advanced" if command.advanced
              keysElement = element
            @instantiateHtmlTemplate container, "#helpDialogEntry", (element) ->
              element.classList.add "advanced" if command.advanced
              descriptionElement = element

          $$(descriptionElement, ".vimiumHelpDescription").textContent = command.description

          keysElement = $$(keysElement, ".vimiumKeyBindings")
          lastElement = null
          for key in command.keys.sort compareKeys
            @instantiateHtmlTemplate keysElement, "#keysTemplate", (element) ->
              lastElement = element
              $$(element, ".vimiumHelpDialogKey").textContent = key
          # And strip off the trailing ", ", if necessary.
          lastElement.removeChild $$ lastElement, ".commaSeparator" if lastElement

          if showAllCommandDetails
            @instantiateHtmlTemplate $$(descriptionElement, ".vimiumHelpDescription"), "#commandNameTemplate", (element) ->
              commandNameElement = $$ element, ".vimiumCopyCommandNameName"
              commandNameElement.textContent = command.command
              commandNameElement.title = "Click to copy \"#{command.command}\" to clipboard."
              commandNameElement.addEventListener "click", ->
                HUD.copyToClipboard commandNameElement.textContent
                HUD.showForDuration("Yanked #{commandNameElement.textContent}.", 2000)

      @showAdvancedCommands(@getShowAdvancedCommands())

      # "Click" the dialog element (so that it becomes scrollable).
      DomUtils.simulateClick @dialogElement

  hide: -> UIComponentServer.hide()
  toggle: -> @hide()

  #
  # Advanced commands are hidden by default so they don't overwhelm new and casual users.
  #
  toggleAdvancedCommands: (event) ->
    vimiumHelpDialogContainer = $ "vimiumHelpDialogContainer"
    scrollHeightBefore = vimiumHelpDialogContainer.scrollHeight
    event.preventDefault()
    showAdvanced = HelpDialog.getShowAdvancedCommands()
    HelpDialog.showAdvancedCommands(!showAdvanced)
    Settings.set("helpDialog_showAdvancedCommands", !showAdvanced)
    # Try to keep the "show advanced commands" button in the same scroll position.
    scrollHeightDelta = vimiumHelpDialogContainer.scrollHeight - scrollHeightBefore
    vimiumHelpDialogContainer.scrollTop += scrollHeightDelta if 0 < scrollHeightDelta

  showAdvancedCommands: (visible) ->
    document.getElementById("toggleAdvancedCommands").textContent =
      if visible then "Hide advanced commands" else "Show advanced commands"

    # Add/remove the showAdvanced class to show/hide advanced commands.
    addOrRemove = if visible then "add" else "remove"
    HelpDialog.dialogElement.classList[addOrRemove] "showAdvanced"

UIComponentServer.registerHandler (event) ->
  switch event.data.name ? event.data
    when "hide" then HelpDialog.hide()
    when "activate"
      HelpDialog.init()
      HelpDialog.show event.data
      Frame.postMessage "registerFrame"
      # If we abandoned (see below) in a mode with a HUD indicator, then we have to reinstate it.
      Mode.setIndicator()
    when "hidden"
      # Unregister the frame, so that it's not available for `gf` or link hints.
      Frame.postMessage "unregisterFrame"
      # Abandon any HUD which might be showing within the help dialog.
      HUD.abandon()

document.addEventListener "DOMContentLoaded", ->
  DomUtils.injectUserCss() # Manually inject custom user styles.

root = exports ? window
root.HelpDialog = HelpDialog
root.isVimiumHelpDialog = true

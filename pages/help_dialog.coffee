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
      HelpDialog.toggleAdvancedCommands, false)

    document.documentElement.addEventListener "click", (event) =>
      @hide() unless @dialogElement.contains event.target
    , false

  show: ({html}) ->
    for own placeholder, htmlString of html
      @dialogElement.querySelector("#help-dialog-#{placeholder}").innerHTML = htmlString

    @showAdvancedCommands(@getShowAdvancedCommands())

    # When command names are shown, clicking on them copies their text to the clipboard (and they can be
    # clicked with link hints).
    for element in @dialogElement.getElementsByClassName "commandName"
      do (element) ->
        element.setAttribute "role", "link"
        element.addEventListener "click", ->
          commandName = element.textContent
          chrome.runtime.sendMessage handler: "copyToClipboard", data: commandName
          HUD.showForDuration("Yanked #{commandName}.", 2000)

    # "Click" the dialog element (so that it becomes scrollable).
    DomUtils.simulateClick @dialogElement

  hide: -> UIComponentServer.hide()
  toggle: -> @hide()

  #
  # Advanced commands are hidden by default so they don't overwhelm new and casual users.
  #
  toggleAdvancedCommands: (event) ->
    event.preventDefault()
    showAdvanced = HelpDialog.getShowAdvancedCommands()
    HelpDialog.showAdvancedCommands(!showAdvanced)
    Settings.set("helpDialog_showAdvancedCommands", !showAdvanced)

  showAdvancedCommands: (visible) ->
    document.getElementById("toggleAdvancedCommands").innerHTML =
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

root = exports ? window
root.HelpDialog = HelpDialog
root.isVimiumHelpDialog = true

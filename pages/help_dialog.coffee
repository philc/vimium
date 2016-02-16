# This overrides the HelpDialog implementation in vimium_frontend.coffee, which prevents us from being able
# to spawn a help dialog within the help dialog UIComponent. As such, we need to provide all the properties
# that we expect on the normal HelpDialog implementation.
#
# NOTE(mrmr1993): In the future, we can move to a single help dialog UIComponent per tab (ie. in the
#   top-level frame), and then we don't need to be concerned about nested help dialog frames.
HelpDialog =
  dialogElement: null
  showing: true

  # This setting is pulled out of local storage. It's false by default.
  getShowAdvancedCommands: -> Settings.get("helpDialog_showAdvancedCommands")

  init: ->
    return if @dialogElement?
    @dialogElement = document.getElementById "vimiumHelpDialog"

    @dialogElement.getElementsByClassName("closeButton")[0].addEventListener("click", (clickEvent) =>
        clickEvent.preventDefault()
        @hide()
      false)
    @dialogElement.getElementsByClassName("optionsPage")[0].addEventListener("click", (clickEvent) ->
        clickEvent.preventDefault()
        chrome.runtime.sendMessage({handler: "openOptionsPageInNewTab"})
      false)
    @dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].addEventListener("click",
      HelpDialog.toggleAdvancedCommands, false)

    document.documentElement.addEventListener "click", (event) =>
      @hide() unless @dialogElement.contains event.target
    , false

  isReady: -> true

  show: (html) ->
    for own placeholder, htmlString of html
      @dialogElement.querySelector("#help-dialog-#{placeholder}").innerHTML = htmlString

    @showAdvancedCommands(@getShowAdvancedCommands())

    # Simulating a click on the help dialog makes it the active element for scrolling.
    DomUtils.simulateClick document.getElementById "vimiumHelpDialog"

  hide: -> UIComponentServer.postMessage "hide"

  toggle: (html) ->
    if @showing then @hide() else @show html

  #
  # Advanced commands are hidden by default so they don't overwhelm new and casual users.
  #
  toggleAdvancedCommands: (event) ->
    event.preventDefault()
    showAdvanced = HelpDialog.getShowAdvancedCommands()
    HelpDialog.showAdvancedCommands(!showAdvanced)
    Settings.set("helpDialog_showAdvancedCommands", !showAdvanced)

  showAdvancedCommands: (visible) ->
    HelpDialog.dialogElement.getElementsByClassName("toggleAdvancedCommands")[0].innerHTML =
      if visible then "Hide advanced commands" else "Show advanced commands"

    # Add/remove the showAdvanced class to show/hide advanced commands.
    addOrRemove = if visible then "add" else "remove"
    HelpDialog.dialogElement.classList[addOrRemove] "showAdvanced"

UIComponentServer.registerHandler (event) ->
  return if event.data == "hide"
  HelpDialog.init()
  HelpDialog.show event.data

root = exports ? window
root.HelpDialog = HelpDialog

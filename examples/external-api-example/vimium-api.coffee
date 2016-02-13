# This code is generic; it defines the interaction between Vimium and this extension.
# It should not be necessary to make changes here; change ./external-commands.coffee instead.

chrome.runtime.onMessageExternal.addListener (request, sender, sendResponse) ->
  # If required, verify the sender here.
  {name, command} = request
  switch name
    when "describe"
      if command of Commands
        sendResponse name: "description", description: Commands[command].description

    when "prepare"
      if command of Commands
        sendResponse name: "ready", background: Commands[command].background

    when "run"
      {count} = request
      if command of Commands
        if Commands[command].blocking
          Commands[command].run count, sendResponse
          true # We will be calling sendResponse(), and we must do so.
        else
          Commands[command].run count
          false # We will not be calling sendResponse().

# We automatically open the options page (to show the available commands) if the available commands have
# changed.

localStorage.commands ||= JSON.stringify []
localStorage.commands = JSON.stringify []
commands = JSON.stringify (key for own key of Commands)

unless commands == localStorage.commands
  localStorage.commands = commands
  chrome.tabs.getSelected null, (tab) ->
    chrome.tabs.create
      url: chrome.extension.getURL "/options.html"
      index: tab.index + 1
      selected: true
      windowId: tab.windowId
      openerTabId: tab.id


# This code is generic; it defines the interaction between Vimium and this extension, and could easily be
# re-used.
chrome.runtime.onMessageExternal.addListener (request, sender, sendResponse) ->
  # If required, verify the sender here.
  {name, command} = request
  switch name
    when "prepare"
      if Commands.syncCommands[command]? or Commands.asyncCommands[command]?
        sendResponse name: "ready", blockKeyboardActivity: Commands.syncCommands[command]?

    when "command"
      {count} = request
      if Commands.syncCommands[command]?
        Commands.syncCommands[command] count, sendResponse
        true # We will be calling sendResponse().

      else if Commands.asyncCommands[command]?
        Commands.asyncCommands[command] count
        false # We not will be calling sendResponse().

      else
        false

    else
      false


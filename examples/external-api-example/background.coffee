
# These are just example commands.  They don't do anything particularly interesting.
commands =
  # These commands are executed asynchronously.
  asyncCommands:
    openVimiumIssues: (count) ->
      chrome.tabs.getSelected null, (tab) ->
        while count--
          chrome.tabs.create
            url: "https://github.com/philc/vimium/issues?q=is%3Aopen+sort%3Aupdated-desc"
            index: tab.index + 1
            selected: true
            windowId: tab.windowId
            openerTabId: tab.id

  # For these commands, Vimium blocks keyboard activity until completion is confirmed.
  syncCommands:
    dummyCommand: (count, sendResponse) ->
      # Do something interesting, probably in the content script, possibly involving user interaction, and
      # perhaps taking some amount of time; then...
      sendResponse {}

# This code is generic; it defines the interaction between Vimium and this extension, and could easily be
# re-used.
chrome.runtime.onMessageExternal.addListener (request, sender, sendResponse) ->
  # If required, verify the sender here.
  {name, command} = request
  switch name
    when "prepare"
      if commands.syncCommands[command]? or commands.asyncCommands[command]?
        sendResponse name: "ready", blockKeyboardActivity: commands.syncCommands[command]?

    when "command"
      {count} = request
      if commands.syncCommands[command]
        commands.syncCommands[command] count, sendResponse
        true # We will be calling sendResponse().
      else if commands.asyncCommands[command]
        commands.asyncCommands[command] count
        false # We not will be calling sendResponse().
      else
        false # We not will be calling sendResponse().

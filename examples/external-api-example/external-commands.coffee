root = exports ? window

# These are just example commands.  They don't do anything particularly interesting.
root.Commands =
  # These commands are executed asynchronously (launch and forget).
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
      # perhaps taking some amount of time to complete; then...
      sendResponse {}

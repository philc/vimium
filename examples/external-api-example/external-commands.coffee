root = exports ? window

# These are just example commands.  They don't do anything particularly interesting.
root.Commands =
  # These commands are executed asynchronously (launch and forget).
  asyncCommands:

    # Open the Vimium Issues page.
    openVimiumIssues: (count) ->
      chrome.tabs.getSelected null, (tab) ->
        while count--
          chrome.tabs.create
            url: "https://github.com/philc/vimium/issues?q=is%3Aopen+sort%3Aupdated-desc"
            index: tab.index + 1
            selected: true
            windowId: tab.windowId
            openerTabId: tab.id

    # Focus the first tab encountered which is playing audio.
    goToAudible: ->
      chrome.windows.getAll {populate: true}, (windows) ->
        for window in windows
          for tab in window.tabs
            continue unless tab.audible
            chrome.tabs.update tab.id, selected: true
            return

  # For these commands, Vimium blocks keyboard activity until completion is confirmed.
  syncCommands:
    alert: (count, sendResponse) ->
      chrome.tabs.getSelected null, (tab) ->
        chrome.tabs.sendMessage tab.id, {name: "alert"}, sendResponse

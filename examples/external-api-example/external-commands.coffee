root = exports ? window

# Implement your own commands here.

root.Commands =
  # Open the Vimium Issues page.
  openVimiumIssues:
    key: "qv"
    description: "Open the Vimium issues page"
    blocking: false
    run: (count) ->
      chrome.tabs.getSelected null, (tab) ->
        while count--
          chrome.tabs.create
            url: "https://github.com/philc/vimium/issues?q=is%3Aopen+sort%3Aupdated-desc"
            index: tab.index + 1
            selected: true
            windowId: tab.windowId
            openerTabId: tab.id

  # Focus the first tab encountered which is playing audio.
  goToAudible:
    key: "qa"
    description: "Focus the current audio tab"
    blocking: false
    run: (count) ->
      chrome.windows.getAll {populate: true}, (windows) ->
        for window in windows
          for tab in window.tabs
            continue unless tab.audible
            chrome.tabs.update tab.id, selected: true
            return

  # Open a "Hello" popup.
  sayHello:
    key: "qh"
    description: "Open a \"Hello\" popup"
    blocking: true
    run: (count, sendResponse) ->
      chrome.tabs.getSelected null, (tab) ->
        chrome.tabs.sendMessage tab.id, {name: "sayHello"}, sendResponse

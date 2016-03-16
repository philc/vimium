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

  # Yank markdown URL; idea from #2054 (@issmirnov).
  yankMarkdownUrl:
    key: "ym"
    description: "Yank the current URL in markdown format"
    blocking: false
    run: (count) ->
      chrome.tabs.getSelected null, ({url, title}) ->
        Clipboard.copy "[#{title}](#{url})"

  # Open a "Hello" popup.
  sayHello:
    key: "qh"
    description: "Open a \"Hello\" popup"
    blocking: true
    run: (count, sendResponse) ->
      chrome.tabs.getSelected null, (tab) ->
        chrome.tabs.sendMessage tab.id, {name: "sayHello"}, sendResponse

Clipboard =
  _createTextArea: ->
    textArea = document.createElement "textarea"
    textArea.style.position = "absolute"
    textArea.style.left = "-100%"
    textArea

  # http://groups.google.com/group/chromium-extensions/browse_thread/thread/49027e7f3b04f68/f6ab2457dee5bf55
  copy: (data) ->
    textArea = @_createTextArea()
    textArea.value = data

    document.body.appendChild(textArea)
    textArea.select()
    document.execCommand("Copy")
    document.body.removeChild(textArea)

  paste: ->
    textArea = @_createTextArea()
    document.body.appendChild(textArea)
    textArea.focus()
    document.execCommand("Paste")
    value = textArea.value
    document.body.removeChild(textArea)
    value

Commands =
  focusFirstAudibleTab:
    description: "Focus the first audible tab."
    command: (options) ->
      chrome.tabs.query {audible: true}, (tabs) ->
        if 0 < tabs.length
          tab = tabs[0]
          chrome.tabs.update tab.id, active: true, ->
            chrome.windows.update tab.windowId, focused: true

  openUrls:
    description: "Open one or more URLs in new tabs."
    extra: "http://edition.cnn.com/ http://www.bbc.com/news"
    command: (options) ->
      chrome.windows.getLastFocused {populate: true}, (win) ->
        tab = (tab for tab in win.tabs when tab.active)[0]
        index = tab.index
        for own key of options
          if key[...7] == "http://" or key[...8] == "https://"
            chrome.tabs.create
              url: key
              index: ++index
              selected: true
              windowId: tab.windowId
              openerTabId: tab.id

chrome.runtime.onMessageExternal.addListener (request) ->
  Commands[request.name]?.command request

# Store documentation in chrome.storage.local (for the options/help page).
helpLines = []
helpLines.push "# Background-page commands"
for own name, command of Commands
  helpLines.push ""
  helpLines.push "# #{command.description}"
  helpLines.push "map X sendMessage name=#{name} extension=#{chrome.runtime.id} #{command.extra ? ''}"

helpLines.push ""
chrome.storage.local.set "contentBackground": helpLines.join "\n"

# Wait a few milliseconds for the help text to be stored, then pop up the options/commands page.
timeoutSet = (ms, func) -> setTimeout func, ms
timeoutSet 500, -> chrome.tabs.create url: chrome.runtime.getURL "commands.html"

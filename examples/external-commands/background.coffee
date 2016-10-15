Commands =
  focusFirstAudibleTab:
    description: "Focus the first audible tab."
    command: (options) ->
      chrome.tabs.query {audible: true}, (tabs) ->
        if 0 < tabs.length
          tab = tabs[0]
          chrome.tabs.update tab.id, active: true, ->
            chrome.windows.update tab.windowId, focused: true

chrome.runtime.onMessageExternal.addListener (request) ->
  Commands[request.name]?.command request

# Show instructions on the background page.
console.log "# Add (and tweak) one or more of the following on the Vimium options page."
console.log "\n# Background-page commands:"
for own name, command of Commands
  console.log "# #{command.description}\n  map X sendMessage name=#{name} extension=#{chrome.runtime.id}"

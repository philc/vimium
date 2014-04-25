injectContentScriptsIntoOpenTabs = ->
  manifest = chrome.runtime.getManifest()
  # All content scripts loaded on every page should go in the same group, assume it is the first
  contentScripts = manifest.content_scripts[0]
  chrome.windows.getAll(null, (windows) ->
    for win in windows
      chrome.tabs.getAllInWindow(win.id, (tabs) ->
        for tab in tabs
           for script in contentScripts.js
             chrome.tabs.executeScript(tab.id, {file: script, allFrames: true})
      )
  )

chrome.runtime.onInstalled.addListener (details) ->
  injectContentScriptsIntoOpenTabs()

injectContentScripts = ->
  manifest = chrome.runtime.getManifest()
  content_scripts = manifest.content_scripts

  insertLocation = document.head.firstChild

  for scriptInfo in content_scripts
    continue if scriptInfo.matches.indexOf("<all_urls>") == -1

    if scriptInfo.js
      for script in scriptInfo.js
        scriptElement = document.createElement "script"
        scriptElement.type = "text/javascript"
        scriptElement.async = false # Don't load out of order!
        scriptElement.src = chrome.runtime.getURL script

        insertLocation.parentElement.insertBefore scriptElement, insertLocation

    if scriptInfo.css
      for style in scriptInfo.css
        styleElement = document.createElement "link"
        styleElement.rel = "stylesheet"
        styleElement.type = "text/css"
        styleElement.href = chrome.runtime.getURL style

        insertLocation.parentElement.insertBefore styleElement, insertLocation

injectContentScripts()

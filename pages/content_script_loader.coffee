injectScript = (script, parentElement = document.head, nextSibling = null) ->
  scriptElement = document.createElement "script"
  scriptElement.type = "text/javascript"
  scriptElement.async = false # Don't load out of order!
  scriptElement.src = script

  parentElement.insertBefore scriptElement, nextSibling

injectStyle = (style, parentElement = document.head, nextSibling = null) ->
  styleElement = document.createElement "link"
  styleElement.rel = "stylesheet"
  styleElement.type = "text/css"
  styleElement.href = style

  parentElement.insertBefore styleElement, nextSibling

injectContentScripts = ->
  manifest = chrome.runtime.getManifest()
  content_scripts = manifest.content_scripts

  insertLocation = document.head.firstChild

  for scriptInfo in content_scripts
    continue if scriptInfo.matches.indexOf("<all_urls>") == -1

    if scriptInfo.js
      for script in scriptInfo.js
        injectScript chrome.runtime.getURL(script), document.head, insertLocation

    if scriptInfo.css
      for style in scriptInfo.css
        injectStyle chrome.runtime.getURL(style), document.head, insertLocation

injectPageScripts = ->
  return unless page_scripts?

  if page_scripts.js
    for script in page_scripts.js
      injectScript script

  if page_scripts.css
    for style in page_scripts.css
      injectStyle style

injectContentScripts()
injectPageScripts()

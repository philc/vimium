# Inject scripts into the page context before page scripts are executed

fetchFileContents = (extensionFileName) ->
  req = new XMLHttpRequest()
  req.open "GET", chrome.runtime.getURL(extensionFileName), false # false => synchronous
  req.send()
  req.responseText

eventName = "reset"
listenerName = "on#{eventName}"
injectScripts = ["pages/addEventListener_hook.js"]

# Store the original value of the event listener if one exists, or null otherwise.
oldValue =
  if document.documentElement.hasAttribute listenerName
    document.documentElement.getAttribute listenerName
  else
    null

firstDocumentElementChild = document.documentElement.firstElementChild

for script in injectScripts
  # Injection method taken from method 3 of this stackoverflow answer http://stackoverflow.com/a/9517879
  document.documentElement.setAttribute listenerName, fetchFileContents script
  document.documentElement.dispatchEvent new CustomEvent eventName

  # Also inject as a script, so that we can still catch any addEventListener call fired at/after
  # DOMContentLoaded.
  scriptEl = document.createElement "script"
  scriptEl.src = chrome.runtime.getURL injectScripts[0]
  document.documentElement.insertBefore scriptEl, firstDocumentElementChild

# Clear our event listener and restore the original, if there was one.
if oldValue?
  document.documentElement.setAttribute listenerName, oldValue
else
  document.documentElement.removeAttribute listenerName

scriptEl = document.createElement "script"
scriptEl.src = chrome.runtime.getURL injectScripts[0]
document.documentElement.insertBefore scriptEl, document.documentElement.firstElementChild

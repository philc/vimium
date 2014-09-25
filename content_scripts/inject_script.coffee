# Inject scripts into the page context before page scripts are executed

fetchFileContents = (extensionFileName) ->
  req = new XMLHttpRequest()
  req.open("GET", chrome.runtime.getURL(extensionFileName), false) # false => synchronous
  req.send()
  req.responseText

eventName = "reset"
injectScripts = ["pages/addEventListener_hook.js"]

# Injection method taken from method 3 of this stackoverflow answer http://stackoverflow.com/a/9517879
for script in injectScripts
  document.documentElement.setAttribute("on#{eventName}", fetchFileContents script)
  document.documentElement.dispatchEvent(new CustomEvent(eventName))
  document.documentElement.removeAttribute("on#{eventName}")

injectScripts = ["pages/addEventListener_hook.js"]

fetchFileContents = (extensionFileName) ->
  req = new XMLHttpRequest()
  req.open("GET", chrome.runtime.getURL(extensionFileName), false) # false => synchronous
  req.send()
  req.responseText

for script in injectScripts
  # Inject the script, which will be executed before the page scripts, as long as it is injected directly as
  # text.
  # TODO(mrmr1993): Find a reasonable way to inline the scripts to inject here at build time, since doing a
  # synchronous XMLHttpRequest will slow down every page load.
  scriptEl = document.createElement "script"
  scriptEl.innerHTML = fetchFileContents script
  document.documentElement.insertBefore scriptEl, document.documentElement.firstElementChild

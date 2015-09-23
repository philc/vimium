injectScripts = ["pages/addEventListener_hook.js"]

for script in injectScripts
  # Inject the script, which will be executed before DOMContentLoaded but after scripts in <head>. Most web
  # developers will hold off creating elements, adding event listeners, etc. until DOMContentLoaded, so we
  # should be able to capture these anyway.
  scriptEl = document.createElement "script"
  scriptEl.src = chrome.runtime.getURL script
  document.documentElement.insertBefore scriptEl, document.documentElement.firstElementChild

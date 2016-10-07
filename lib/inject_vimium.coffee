
if chrome.extension?.getBackgroundPage?() == window
  # This is the background page.
  # Important: All resources listed here must also be listed in ../pages/vimium_resources.html.
  jss = [
    "lib/utils.js",
    "lib/keyboard_utils.js",
    "lib/dom_utils.js",
    "lib/rect.js",
    "lib/handler_stack.js",
    "lib/settings.js",
    "lib/find_mode_history.js",
    "content_scripts/mode.js",
    "content_scripts/ui_component.js",
    "content_scripts/link_hints.js",
    "content_scripts/vomnibar.js",
    "content_scripts/scroller.js",
    "content_scripts/marks.js",
    "content_scripts/mode_insert.js",
    "content_scripts/mode_find.js",
    "content_scripts/mode_key_handler.js",
    "content_scripts/mode_visual.js",
    "content_scripts/hud.js",
    "content_scripts/vimium_frontend.js",
  ]

  css = [
    "content_scripts/vimium.css",
  ]

  # Listen for pages requesting that Vimium be loaded.
  chrome.runtime.onMessage.addListener ({handler}, sender, sendResponse) ->
    if handler == "injectVimium"
      tabId = sender.tab.id
      frameId = sender.frameId

      for file in jss
        chrome.tabs.executeScript tabId, {file, frameId, runAt: "document_start"}, ->
          chrome.runtime.lastError

      for file in css
        chrome.tabs.insertCSS tabId, {file, frameId}, ->
          chrome.runtime.lastError

    # Ensure that the sendResponse callback is freed.
    false

  # If Vimium is upgrading, then there may already be open tabs. We (re-)inject the content scripts so that
  # Vimium works again.
  chrome.runtime.onInstalled.addListener ({reason}) ->
    unless reason in ["chrome_update", "shared_module_update"]
      chrome.tabs.query {status: "complete"}, (tabs) ->
        for tab in tabs
          chrome.tabs.executeScript tab.id, {file: "lib/inject_vimium.js", allFrames: true, matchAboutBlank: true}, ->
            chrome.runtime.lastError

else
  # This is not the background page.
  vimiumEventListeners = {}

  eventHookLocations =
    keydown: window
    keypress: window
    keyup: window
    click: window
    focus: window
    blur: window
    mousedown: window
    scroll: window
    DOMActivate: document

  # Install placeholder event listeners as early as possible, so that the page cannot register any event
  # handlers before us.  The actual listener functions are added later (in vimium_frontend.coffee).  Note: We
  # install these listeners even if Vimium is disabled.  See comment in commit 6446cf04c7b44c3d419dc450a73b60bcaf5cdf02.
  for own type, element of eventHookLocations
    do (type) -> element.addEventListener type, (-> vimiumEventListeners[type]? arguments...), true

  # Make these placeholder event listeners available to vimium_frontend.coffee, which later installs the
  # real listener functions.
  root = exports ? window
  root.vimiumEventTypes = (type for own type of eventHookLocations)
  root.installVimiumEventListener = (type, callback) -> vimiumEventListeners[type] = callback

  unless chrome.extension?.getBackgroundPage?
    # This is *not* one of Vimium's own pages (e.g. the options page).  Those pages inject the Vimium content
    # scripts themselves.  For other pages, we ask the background page to inject the scripts (via the message
    # handler above).
    #
    # We do not activate Vimium in very-small frames (it's no use there, and initializing Vimium takes time
    # and requires memory).
    if window.top == window.self or 3 <= window.innerWidth or 3 <= window.innerHeight
      chrome.runtime.sendMessage handler: "injectVimium"
    else
      window.addEventListener "resize", resizeHandler = ->
        if 3 <= window.innerWidth or 3 <= window.innerHeight
          chrome.runtime.sendMessage handler: "injectVimium"
          window.removeEventListener "resize", resizeHandler


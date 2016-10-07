
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

if chrome.extension?.getBackgroundPage?() == window
  # This is the background page.  Listen for pages requesting that Vimium be loaded.
  chrome.runtime.onMessage.addListener ({handler}, sender, sendResponse) ->
    if handler == "injectVimium"
      tabId = sender.tab.id
      frameId = sender.frameId

      for file in jss
        chrome.tabs.executeScript tabId, {file, frameId, runAt: "document_start"}

      for file in css
        chrome.tabs.insertCSS tabId, {file, frameId}

    # Ensure that the sendResponse callback is freed.
    false

  # If Vimium is upgrading, then there may already be open tabs. We (re-)inject the content scripts so that
  # Vimium works again.
  chrome.runtime.onInstalled.addListener ({reason}) ->
    unless reason in ["chrome_update", "shared_module_update"]
      chrome.tabs.query {status: "complete"}, (tabs) ->
        for tab in tabs
          chrome.tabs.executeScript tab.id, {file: "lib/inject_vimium.js", allFrames: true}, ->
            # Chrome complains if we do not check for errors.
            chrome.runtime.lastError

else
  # This is not the background page.  Request that Vimium's content scripts be loaded.  This message is
  # received by the background page and handled by the listener above.
  chrome.runtime.sendMessage handler: "injectVimium"


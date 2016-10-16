
documentReady = do ->
  [isReady, callbacks] = [document.readyState != "loading", []]
  unless isReady
    window.addEventListener "DOMContentLoaded", onDOMContentLoaded = ->
      window.removeEventListener "DOMContentLoaded", onDOMContentLoaded
      isReady = true
      callback() for callback in callbacks
      callbacks = null

  (callback) -> if isReady then callback() else callbacks.push callback

documentReady ->
  chrome.storage.local.get null, (items) ->
    for id in ["contentBackground", "contentForeground"]
      element = document.getElementById id
      element.innerHTML = items[id]


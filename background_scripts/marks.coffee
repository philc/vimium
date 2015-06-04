
Marks =
  marks: {}

  # This returns the key which is used for storing mark locations in chrome.storage.local.
  getLocationKey: (markName) -> "vimiumGlobalMark|#{markName}"

  create: (req, sender) ->
    chrome.storage.local.get "vimiumSecret", (items) =>
      item = {}
      item[@getLocationKey req.markName] =
        vimiumSecret: items.vimiumSecret
        tabId: sender.tab.id
        url: sender.tab.url
        scrollX: req.scrollX
        scrollY: req.scrollY
      console.log item
      chrome.storage.local.set item

  goto: (req, sender) ->
    key = @getLocationKey req.markName
    chrome.storage.local.get [ "vimiumSecret", key ], (items) =>
      markInfo = items[key]
      if not markInfo
        # The mark is not defined.
        chrome.tabs.sendMessage sender.tab.id,
          name: "showHUDforDuration",
          text: "Global mark not set: '#{req.markName}'."
          duration: 1000
      else if markInfo.vimiumSecret != items.vimiumSecret
        # This is a different Vimium instantiation, so markInfo.tabId is definitely out of date.
        @focusOrLaunch markInfo
      else
        # Check whether markInfo.tabId still exists.
        { tabId, url, scrollX, scrollY } = markInfo
        chrome.tabs.get tabId, (tab) =>
          if chrome.runtime.lastError or not tab
            # The tab no longer exists.
            @focusOrLaunch markInfo
          else
            # The original tab still exists.
            chrome.tabs.update tabId, { selected: true }, ->
              chrome.tabs.sendMessage tabId,
                { name: "setScrollPosition", scrollX: scrollX, scrollY: scrollY }, ->
                  chrome.tabs.sendMessage tabId,
                    name: "showHUDforDuration",
                    text: "Jumped to global mark '#{req.markName}'."
                    duration: 1000

  # The tab we're trying to find no longer exists.  Either find another tab with a matching URL and use it, or
  # create a new tab.
  focusOrLaunch: (info) ->
    console.log info

root = exports ? window
root.Marks = Marks

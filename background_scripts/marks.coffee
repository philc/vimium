
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
        markName: req.markName
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
        chrome.tabs.get markInfo.tabId, (tab) =>
          if chrome.runtime.lastError or not tab
            # The original tab no longer exists.
            @focusOrLaunch markInfo
          else
            # The original tab still exists.
            @gotoPositionInTab markInfo

  gotoPositionInTab: ({ tabId, scrollX, scrollY, markName }) ->
    chrome.tabs.update tabId, { selected: true }, ->
      chrome.tabs.sendMessage tabId,
        { name: "setScrollPosition", scrollX: scrollX, scrollY: scrollY }, ->
          chrome.tabs.sendMessage tabId,
            name: "showHUDforDuration",
            text: "Jumped to global mark '#{markName}'."
            duration: 1000

  # The tab we're trying to find no longer exists.  Either find another tab with a matching URL and use it, or
  # create a new tab.
  focusOrLaunch: (markInfo) ->
    chrome.windows.getAll { populate: true }, (windows) =>
      baseUrl = @getBaseUrl markInfo.url
      for window in windows
        for tab in window.tabs
          if baseUrl == @getBaseUrl tab.url
            # We have a matching tab.  We'll use it.
            return @gotoPositionInTab extend markInfo, tabId: tab.id

  getBaseUrl: (url) -> url.split("#")[0]

root = exports ? window
root.Marks = Marks

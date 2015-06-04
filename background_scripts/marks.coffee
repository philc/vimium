
Marks =
  # This returns the key which is used for storing mark locations in chrome.storage.local.
  getLocationKey: (markName) -> "vimiumGlobalMark|#{markName}"

  # Get the part of a URL we use for matching here (that is, everything up to the first anchor).
  getBaseUrl: (url) -> url.split("#")[0]

  # Create a global mark.  We record vimiumSecret with the mark so that we can tell later, when the mark is
  # used, whether this is the original Vimium instantiation or a subsequent instantiation.  This affects
  # whether or not tabId can be considered valid.
  create: (req, sender) ->
    chrome.storage.local.get "vimiumSecret", (items) =>
      item = {}
      item[@getLocationKey req.markName] =
        vimiumSecret: items.vimiumSecret
        tabId: sender.tab.id
        url: @getBaseUrl sender.tab.url
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
        # Check whether markInfo.tabId still exists.  According to here (https://developer.chrome.com/extensions/tabs),
        # tab Ids are unqiue within a Chrome session.  So, if we find a match, we can use.
        chrome.tabs.get markInfo.tabId, (tab) =>
          if not chrome.runtime.lastError and tab?.url and markInfo.url == @getBaseUrl tab.url
            # The original tab still exists.
            @gotoPositionInTab markInfo
          else
            # The original tab no longer exists.
            @focusOrLaunch markInfo

  gotoPositionInTab: ({ tabId, scrollX, scrollY, markName }) ->
    chrome.tabs.update tabId, { selected: true }, ->
      chrome.tabs.sendMessage tabId,
        { name: "setScrollPosition", scrollX: scrollX, scrollY: scrollY }, ->
          chrome.tabs.sendMessage tabId,
            name: "showHUDforDuration",
            text: "Jumped to global mark '#{markName}'."
            duration: 1000

  # The tab we're trying to find no longer exists.  We either find another tab with a matching URL and use it,
  # or we create a new tab.
  focusOrLaunch: (markInfo) ->
    chrome.windows.getAll { populate: true }, (windows) =>
      for window in windows
        for tab in window.tabs
          if markInfo.url == @getBaseUrl tab.url
            # We have a matching tab: use it.
            @gotoPositionInTab extend markInfo, tabId: tab.id
            return
      # There is no existing matching tab, we'll have to create one.
      chrome.tabs.create { url: @getBaseUrl(markInfo.url) }, (tab) =>
        # Note. tabLoadedHandlers is defined in "main.coffee".  The handler below will be called when the tab
        # is loaded, its DOM is ready and it registers with the background page.
        tabLoadedHandlers[tab.id] = => @gotoPositionInTab extend markInfo, tabId: tab.id

root = exports ? window
root.Marks = Marks


Marks =
  # This returns the key which is used for storing mark locations in chrome.storage.sync.
  getLocationKey: (markName) -> "vimiumGlobalMark|#{markName}"

  # Get the part of a URL we use for matching here (that is, everything up to the first anchor).
  getBaseUrl: (url) -> url.split("#")[0]

  # Create a global mark.  We record vimiumSecret with the mark so that we can tell later, when the mark is
  # used, whether this is the original Vimium session or a subsequent session.  This affects whether or not
  # tabId can be considered valid.
  create: (req, sender) ->
    chrome.storage.local.get "vimiumSecret", (items) =>
      markInfo =
        vimiumSecret: items.vimiumSecret
        markName: req.markName
        url: @getBaseUrl sender.tab.url
        tabId: sender.tab.id
        scrollX: req.scrollX
        scrollY: req.scrollY

      if markInfo.scrollX? and markInfo.scrollY?
        @saveMark markInfo
      else
        # The front-end frame hasn't provided the scroll position (because it's not the top frame within its
        # tab).  We need to ask the top frame what its scroll position is.
        chrome.tabs.sendMessage sender.tab.id, name: "getScrollPosition", (response) =>
          @saveMark extend markInfo, scrollX: response.scrollX, scrollY: response.scrollY

  saveMark: (markInfo) ->
    item = {}
    item[@getLocationKey markInfo.markName] = markInfo
    chrome.storage.sync.set item

  # Goto a global mark.  We try to find the original tab.  If we can't find that, then we try to find another
  # tab with the original URL, and use that.  And if we can't find such an existing tab, then we create a new
  # one.  Whichever of those we do, we then set the scroll position to the original scroll position.
  goto: (req, sender) ->
    chrome.storage.local.get "vimiumSecret", (items) =>
      vimiumSecret = items.vimiumSecret
      key = @getLocationKey req.markName
      chrome.storage.sync.get key, (items) =>
        markInfo = items[key]
        if markInfo.vimiumSecret != vimiumSecret
          # This is a different Vimium instantiation, so markInfo.tabId is definitely out of date.
          @focusOrLaunch markInfo, req
        else
          # Check whether markInfo.tabId still exists.  According to here (https://developer.chrome.com/extensions/tabs),
          # tab Ids are unqiue within a Chrome session.  So, if we find a match, we can use it.
          chrome.tabs.get markInfo.tabId, (tab) =>
            if not chrome.runtime.lastError and tab?.url and markInfo.url == @getBaseUrl tab.url
              # The original tab still exists.
              @gotoPositionInTab markInfo
            else
              # The original tab no longer exists.
              @focusOrLaunch markInfo, req

  # Focus an existing tab and scroll to the given position within it.
  gotoPositionInTab: ({ tabId, scrollX, scrollY, markName }) ->
    chrome.tabs.update tabId, { active: true }, ->
      chrome.tabs.sendMessage tabId, {name: "setScrollPosition", scrollX, scrollY}

  # The tab we're trying to find no longer exists.  We either find another tab with a matching URL and use it,
  # or we create a new tab.
  focusOrLaunch: (markInfo, req) ->
    # If we're not going to be scrolling to a particular position in the tab, then we choose all tabs with a
    # matching URL prefix.  Otherwise, we require an exact match (because it doesn't make sense to scroll
    # unless there's an exact URL match).
    query = if markInfo.scrollX == markInfo.scrollY == 0 then "#{markInfo.url}*" else markInfo.url
    chrome.tabs.query { url: query }, (tabs) =>
      if 0 < tabs.length
        # We have at least one matching tab.  Pick one and go to it.
        @pickTab tabs, (tab) =>
          @gotoPositionInTab extend markInfo, tabId: tab.id
      else
        # There is no existing matching tab, we'll have to create one.
        TabOperations.openUrlInNewTab (extend req, url: @getBaseUrl markInfo.url), (tab) =>
          # Note. tabLoadedHandlers is defined in "main.coffee".  The handler below will be called when the tab
          # is loaded, its DOM is ready and it registers with the background page.
          tabLoadedHandlers[tab.id] = => @gotoPositionInTab extend markInfo, tabId: tab.id

  # Given a list of tabs candidate tabs, pick one.  Prefer tabs in the current window and tabs with shorter
  # (matching) URLs.
  pickTab: (tabs, callback) ->
    chrome.windows.getCurrent ({ id }) ->
      # Prefer tabs in the current window, if there are any.
      tabsInWindow = tabs.filter (tab) -> tab.windowId == id
      tabs = tabsInWindow if 0 < tabsInWindow.length
      # If more than one tab remains and the current tab is still a candidate, then don't pick the current
      # tab (because jumping to it does nothing).
      tabs = (tab for tab in tabs when not tab.active) if 1 < tabs.length
      # Prefer shorter URLs.
      tabs.sort (a,b) -> a.url.length - b.url.length
      callback tabs[0]

root = exports ? window
root.Marks = Marks

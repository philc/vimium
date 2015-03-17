#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
Vomnibar =
  vomnibarUI: null

  # frameId here (and below) is the ID of the frame from which this request originates, which may be different
  # from the current frame.
  activate: (frameId) -> @open frameId, {completer:"omni"}
  activateInNewTab: (frameId) -> @open frameId, {
    completer: "omni"
    selectFirst: false
    newTab: true
  }
  activateTabSelection: (frameId) -> @open frameId, {
    completer: "tabs"
    selectFirst: true
  }
  activateBookmarks: (frameId) -> @open frameId, {
    completer: "bookmarks"
    selectFirst: true
  }
  activateBookmarksInNewTab: (frameId) -> @open frameId, {
    completer: "bookmarks"
    selectFirst: true
    newTab: true
  }
  activateEditUrl: (frameId) -> @open frameId, {
    completer: "omni"
    selectFirst: false
    query: window.location.href
  }
  activateEditUrlInNewTab: (frameId) -> @open frameId, {
    completer: "omni"
    selectFirst: false
    query: window.location.href
    newTab: true
  }

  init: ->
    unless @vomnibarUI?
      @vomnibarUI = new UIComponent "pages/vomnibar.html", "vomnibarFrame", (event) =>
        if event.data == "hide"
          @vomnibarUI.hide()
          @vomnibarUI.postMessage "hidden"


  # This function opens the vomnibar. It accepts options, a map with the values:
  #   completer   - The completer to fetch results from.
  #   query       - Optional. Text to prefill the Vomnibar with.
  #   selectFirst - Optional, boolean. Whether to select the first entry.
  #   newTab      - Optional, boolean. Whether to open the result in a new tab.
  open: (frameId, options) -> @vomnibarUI.activate extend options, { frameId }

root = exports ? window
root.Vomnibar = Vomnibar

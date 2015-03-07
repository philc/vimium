#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
Vomnibar =
  vomnibarUI: null

  activate: -> @open {completer:"omni"}
  activateInNewTab: -> @open {
    completer: "omni"
    selectFirst: false
    newTab: true
  }
  activateTabSelection: -> @open {
    completer: "tabs"
    selectFirst: true
  }
  activateBookmarks: -> @open {
    completer: "bookmarks"
    selectFirst: true
  }
  activateBookmarksInNewTab: -> @open {
    completer: "bookmarks"
    selectFirst: true
    newTab: true
  }
  activateEditUrl: -> @open {
    completer: "omni"
    selectFirst: false
    query: window.location.href
  }
  activateEditUrlInNewTab: -> @open {
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
  open: (options) -> @vomnibarUI.activate options

root = exports ? window
root.Vomnibar = Vomnibar

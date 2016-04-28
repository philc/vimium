#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
Vomnibar =
  vomnibarUI: null

  # Parse any additional options from the command's registry entry.  Currently, this only includes a flag of
  # the form "keyword=X", for direct activation of a custom search engine.
  parseRegistryEntry: (registryEntry = { options: [] }, callback = null) ->
    searchEngines = Settings.get("searchEngines") ? ""
    SearchEngines.refreshAndUse searchEngines, (engines) ->
      callback? registryEntry.options

  # sourceFrameId here (and below) is the ID of the frame from which this request originates, which may be different
  # from the current frame.

  activate: (sourceFrameId, registryEntry) ->
    @parseRegistryEntry registryEntry, (options) =>
      @open sourceFrameId, extend options, completer:"omni"

  activateInNewTab: (sourceFrameId, registryEntry) ->
    @parseRegistryEntry registryEntry, (options) =>
      @open sourceFrameId, extend options, completer:"omni", newTab: true

  activateTabSelection: (sourceFrameId) -> @open sourceFrameId, {
    completer: "tabs"
    selectFirst: true
  }
  activateBookmarks: (sourceFrameId) -> @open sourceFrameId, {
    completer: "bookmarks"
    selectFirst: true
  }
  activateBookmarksInNewTab: (sourceFrameId) -> @open sourceFrameId, {
    completer: "bookmarks"
    selectFirst: true
    newTab: true
  }
  activateEditUrl: (sourceFrameId) -> @open sourceFrameId, {
    completer: "omni"
    selectFirst: false
    query: window.location.href
  }
  activateEditUrlInNewTab: (sourceFrameId) -> @open sourceFrameId, {
    completer: "omni"
    selectFirst: false
    query: window.location.href
    newTab: true
  }

  init: ->
    @vomnibarUI ?= new UIComponent "pages/vomnibar.html", "vomnibarFrame", ->

  # This function opens the vomnibar. It accepts options, a map with the values:
  #   completer   - The completer to fetch results from.
  #   query       - Optional. Text to prefill the Vomnibar with.
  #   selectFirst - Optional, boolean. Whether to select the first entry.
  #   newTab      - Optional, boolean. Whether to open the result in a new tab.
  open: (sourceFrameId, options) ->
    if @vomnibarUI?
      # The Vomnibar cannot coexist with the help dialog (it causes focus issues).
      HelpDialog.abort()
      @vomnibarUI.activate extend options, { name: "activate", sourceFrameId, focus: true }

root = exports ? window
root.Vomnibar = Vomnibar

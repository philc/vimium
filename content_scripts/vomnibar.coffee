#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
Vomnibar =
  vomnibarUI: null

  # Extract any additional options from the command's registry entry.
  extractOptionsFromRegistryEntry: (registryEntry, callback) ->
    callback? extend {}, registryEntry.options

  # sourceFrameId here (and below) is the ID of the frame from which this request originates, which may be different
  # from the current frame.

  activate: (sourceFrameId, registryEntry) ->
    @extractOptionsFromRegistryEntry registryEntry, (options) =>
      @open sourceFrameId, extend options, completer:"omni"

  activateInNewTab: (sourceFrameId, registryEntry) ->
    @extractOptionsFromRegistryEntry registryEntry, (options) =>
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
    @init()
    # The Vomnibar cannot coexist with the help dialog (it causes focus issues).
    HelpDialog.abort()
    @vomnibarUI.activate extend options, { name: "activate", sourceFrameId, focus: true }

root = exports ? (window.root ?= {})
root.Vomnibar = Vomnibar
extend window, root unless exports?

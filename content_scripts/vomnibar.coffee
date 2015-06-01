#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
Vomnibar =
  vomnibarUI: null

  # Parse any additional options from the command's registry entry.  Currently, this only includes a flag of
  # the form "keyword=X", for direct activation of a custom search engine.
  parseRegistryEntry: (registryEntry = { options: [] }, callback = null) ->
    options = {}
    searchEngines = Settings.get("searchEngines") ? ""
    SearchEngines.refreshAndUse searchEngines, (engines) ->
      for option in registryEntry.options
        [ key, value ] = option.split "="
        switch key
          when "keyword"
            if value? and engines[value]?
              options.keyword = value
            else
              console.log "Vimium configuration error: no such custom search engine: #{option}."
          else
              console.log "Vimium configuration error: unused flag: #{option}."

      callback? options

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
    unless @vomnibarUI?
      @vomnibarUI = new UIComponent "pages/vomnibar.html", "vomnibarFrame", (event) =>
        @vomnibarUI.hide() if event.data == "hide"
      # Whenever the window receives the focus, we tell the Vomnibar UI that it has been hidden (regardless of
      # whether it was previously visible).
      window.addEventListener "focus", (event) =>
        @vomnibarUI.postMessage "hidden" if event.target == window; true


  # This function opens the vomnibar. It accepts options, a map with the values:
  #   completer   - The completer to fetch results from.
  #   query       - Optional. Text to prefill the Vomnibar with.
  #   selectFirst - Optional, boolean. Whether to select the first entry.
  #   newTab      - Optional, boolean. Whether to open the result in a new tab.
  open: (sourceFrameId, options) -> @vomnibarUI.activate extend options, { sourceFrameId }

root = exports ? window
root.Vomnibar = Vomnibar

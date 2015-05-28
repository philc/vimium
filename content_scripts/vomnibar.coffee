#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
Vomnibar =
  vomnibarUI: null

  # sourceFrameId here (and below) is the ID of the frame from which this request originates, which may be different
  # from the current frame.
  activate: (sourceFrameId) -> @open sourceFrameId, {completer:"omni"}
  activateInNewTab: (sourceFrameId) -> @open sourceFrameId, {
    completer: "omni"
    selectFirst: false
    newTab: true
  }
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

  activateEditUrl: (sourceFrameId, text = window.location.href) ->

    @open sourceFrameId,
      completer: "omni"
      selectFirst: false
      query: text

  activateEditUrlInNewTab: (sourceFrameId, text = window.location.href) ->
    @open sourceFrameId,
      completer: "omni"
      selectFirst: false
      query: text
      newTab: true

  activateCustomSearch: (sourceFrameId) -> new CustomSearchMode this, sourceFrameId, false
  activateCustomSearchInNewTab: (sourceFrameId) -> new CustomSearchMode this, sourceFrameId, true

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

class CustomSearchMode extends Mode
  constructor: (@vomnibar, @sourceFrameId, @newTab = false) ->
    @engines = Utils.parseCustomSearchEngines settings.get "searchEngines"
    @keywords = (key for own key of @engines).sort()
    @search = ""

    super
      name: "custom-search"
      exitOnEscape: true
      indicator: @getIndicator()
      keydown: (event) => @handleKeydown event
      keypress: (event) => @handleKeypress event
      keyup: => @stopBubblingAndFalse

    @exit "No custom search engines" unless 0 < @keywords.length

  getKeywords: ->
    @keywords.filter (keyword) => keyword.startsWith @search

  getIndicator: ->
    keywords = @getKeywords()
    if 10 < keywords.length
      keywords = [ keywords[...10]..., "..." ]
    keywords = keywords.join ","
    "Search: " + keywords

  handleKeydown: (event) ->
    if event.keyCode == keyCodes.enter
      @exit null, => @activate @getKeywords()[0]
    else if event.keyCode in [ keyCodes.backspace, keyCodes.deleteKey ]
      if @search.length == 0
        @exit()
      else
        @search = @search[0...@search.length - 1]
        @setIndicator @getIndicator()
    else
      return @stopBubblingAndTrue

    DomUtils.suppressEvent event
    @stopBubblingAndTrue

  handleKeypress: (event) ->
    keyChar = String.fromCharCode event.charCode
    @search += String.fromCharCode event.charCode
    keywords = @getKeywords()
    switch keywords.length
      when 0
        @exit "No matching keyword."
      when 1
        @exit null, => @activate keywords[0]
      else
        @setIndicator @getIndicator()
    @stopBubblingAndFalse

  activate: (keyword = null) ->
    if @newTab
      @vomnibar.activateEditUrlInNewTab @sourceFrameId, "#{keyword} " if keyword?
    else
      @vomnibar.activateEditUrl @sourceFrameId, "#{keyword} " if keyword?

  exit: (msg = null, continuation = null) ->
    super()
    HUD.showForDuration msg, 1000 if msg?
    continuation?()

root = exports ? window
root.Vomnibar = Vomnibar

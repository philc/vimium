#
# This controls the contents of the Vomnibar iframe. We use an iframe to avoid changing the selection on the
# page (useful for bookmarklets), ensure that the Vomnibar style is unaffected by the page, and simplify key
# handling in vimium_frontend.coffee
#
Vomnibar =
  vomnibarUI: null # the dialog instance for this window
  getUI: -> @vomnibarUI
  completers: {}

  getCompleter: (name) ->
    @completers[name] ?= new BackgroundCompleter name

  activate: (userOptions) ->
    options =
      completer: "omni"
      query: ""
      newTab: false
      selectFirst: false
    extend options, userOptions
    extend options, refreshInterval: if options.completer == "omni" then 100 else 0

    completer = @getCompleter options.completer
    @vomnibarUI ?= new VomnibarUI()
    completer.refresh @vomnibarUI
    @vomnibarUI.setInitialSelectionValue if options.selectFirst then 0 else -1
    @vomnibarUI.setCompleter completer
    @vomnibarUI.setRefreshInterval options.refreshInterval
    @vomnibarUI.setForceNewTab options.newTab
    @vomnibarUI.setQuery options.query
    @vomnibarUI.update true

  hide: -> @vomnibarUI?.hide()
  onHidden: -> @vomnibarUI?.onHidden()

class VomnibarUI
  constructor: ->
    @refreshInterval = 0
    @postHideCallback = null
    @initDom()

  setQuery: (query) -> @input.value = query
  setInitialSelectionValue: (@initialSelectionValue) ->
  setRefreshInterval: (@refreshInterval) ->
  setForceNewTab: (@forceNewTab) ->
  setCompleter: (@completer) -> @reset()
  setKeywords: (@keywords) ->

  # The sequence of events when the vomnibar is hidden is as follows:
  # 1. Post a "hide" message to the host page.
  # 2. The host page hides the vomnibar.
  # 3. When that page receives the focus, and it posts back a "hidden" message.
  # 3. Only once the "hidden" message is received here is any required action  invoked (in onHidden).
  # This ensures that the vomnibar is actually hidden before any new tab is created, and avoids flicker after
  # opening a link in a new tab then returning to the original tab (see #1485).
  hide: (@postHideCallback = null) ->
    UIComponentServer.postMessage "hide"
    @reset()

  onHidden: ->
    @postHideCallback?()
    @postHideCallback = null

  reset: ->
    @clearUpdateTimer()
    @completionList.style.display = ""
    @input.value = ""
    @completions = []
    @previousAutoSelect = null
    @previousInputValue = null
    @suppressedLeadingKeyword = null
    @previousLength = 0
    @selection = @initialSelectionValue
    @keywords = []

  updateSelection: ->
    # We retain global state here (previousAutoSelect) to tell if a search item (for which autoSelect is set)
    # has just appeared or disappeared. If that happens, we set @selection to 0 or -1.
    if 0 < @completions.length
      @selection = 0 if @completions[0].autoSelect and not @previousAutoSelect
      @selection = -1 if @previousAutoSelect and not @completions[0].autoSelect
      @previousAutoSelect = @completions[0].autoSelect
    else
      @previousAutoSelect = null

    # For custom search engines, we suppress the leading term (e.g. the "w" of "w query terms") within the
    # vomnibar input.
    if @completions[0]?.suppressLeadingKeyword and not @suppressedLeadingKeyword?
      queryTerms = @input.value.trim().split /\s+/
      @suppressedLeadingKeyword = queryTerms[0]
      @input.value = queryTerms[1..].join " "

    # For suggestions from search-engine completion, we copy the suggested text into the input when selected,
    # and revert when not.  This allows the user to select a suggestion and then continue typing.
    if 0 <= @selection and @completions[@selection].insertText?
      @previousInputValue ?=
        value: @input.value
        selectionStart: @input.selectionStart
        selectionEnd: @input.selectionEnd
      @input.value = @completions[@selection].insertText + (if @selection == 0 then "" else " ")
    else if @previousInputValue?
        @input.value = @previousInputValue.value
        if @previousInputValue.selectionStart? and @previousInputValue.selectionEnd? and
          @previousInputValue.selectionStart != @previousInputValue.selectionEnd
            @input.setSelectionRange @previousInputValue.selectionStart, @previousInputValue.selectionEnd
        @previousInputValue = null

    # Highlight the the selected entry, and only the selected entry.
    @highlightTheSelectedEntry()

  highlightTheSelectedEntry: ->
    for i in [0...@completionList.children.length]
      @completionList.children[i].className = (if i == @selection then "vomnibarSelected" else "")

  highlightCommonMatches: (response) ->
    # For custom search engines, add characters to the input which are:
    #   - not in the query/input
    #   - in all completions
    # and select the added text.

    # Bail if we don't yet have the background completer's final word on the current query.
    return unless response.mayCacheResults

    # Bail if there's an update pending (because then @input and the completion state are out of sync).
    return if @updateTimer?

    @previousLength ?= @input.value.length
    previousLength = @previousLength
    currentLength = @input.value.length
    @previousLength = currentLength

    # We only highlight matches if the query gets longer (so, not on deletions).
    return unless previousLength < currentLength

    # Get the completions for which we can highlight matching text.
    completions = @completions.filter (completion) ->
      completion.highlightCommonMatches? and completion.highlightCommonMatches

    # Bail if these aren't any completions.
    return unless 0 < completions.length

    # Fetch the query and the suggestion texts.
    query = @input.value.ltrim().split(/\s+/).join(" ").toLowerCase()
    suggestions = completions.map (completion) -> completion.title

    # Ensure that the query is a prefix of all of the suggestions.
    for suggestion in suggestions
      return unless 0 == suggestion.toLowerCase().indexOf query

    # Calculate the length of the shotest suggestion.
    length = suggestions[0].length
    length = Math.min length, suggestion.length for suggestion in suggestions

    # Find the the length of the longest common continuation.
    length = do ->
      for index in [query.length...length]
        for suggestion in suggestions
          return index if suggestions[0][index].toLowerCase() != suggestion[index].toLowerCase()
      length

    # Bail if there's nothing to complete.
    return unless  query.length < length

    # Don't highlight only whitespace (that is, the entire common text consists only of whitespace).
    return if /^\s+$/.test suggestions[0].slice query.length, length

    # Highlight match.
    @input.value = suggestions[0].slice 0, length
    @input.setSelectionRange query.length, length

  #
  # Returns the user's action ("up", "down", "tab", "enter", "dismiss", "delete" or null) based on their
  # keypress.
  # We support the arrow keys and other shortcuts for moving, so this method hides that complexity.
  #
  actionFromKeyEvent: (event) ->
    key = KeyboardUtils.getKeyChar(event)
    if (KeyboardUtils.isEscape(event))
      return "dismiss"
    else if (key == "up" ||
        (event.shiftKey && event.keyCode == keyCodes.tab) ||
        (event.ctrlKey && (key == "k" || key == "p")))
      return "up"
    else if (event.keyCode == keyCodes.tab && !event.shiftKey)
      return "tab"
    else if (key == "down" ||
        (event.ctrlKey && (key == "j" || key == "n")))
      return "down"
    else if (event.keyCode == keyCodes.enter)
      return "enter"
    else if event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey
      return "delete"
    null

  onKeydown: (event) =>
    action = @actionFromKeyEvent(event)
    return true unless action # pass through

    openInNewTab = @forceNewTab ||
      (event.shiftKey || event.ctrlKey || KeyboardUtils.isPrimaryModifierKey(event))
    if (action == "dismiss")
      @hide()
    else if action in [ "tab", "down" ]
      if action == "tab"
        if @inputContainsASelectionRange()
          # The first tab collapses the selection to the end.
          window.getSelection()?.collapseToEnd()
        else
          # Subsequent tabs behave the same as "down".
          action = "down"
      if action == "down"
        @selection += 1
        @selection = @initialSelectionValue if @selection == @completions.length
        @updateSelection()
    else if (action == "up")
      @selection -= 1
      @selection = @completions.length - 1 if @selection < @initialSelectionValue
      @updateSelection()
    else if (action == "enter")
      if @selection == -1
        # The user has not selected a suggestion.
        query = @input.value.trim()
        # <Enter> on an empty vomnibar is a no-op.
        return unless 0 < query.length
        if @suppressedLeadingKeyword?
          # This is a custom search engine completion.  Because of the way we add and highlight the text
          # common to all completions in the input (highlightCommonMatches), the text in the input might not
          # correspond to any of the completions.  So we fire the query off to the background page and use the
          # completion at the top of the list (which will be the right one).
          @update true, =>
            if @completions[0]
              completion = @completions[0]
              @hide -> completion.performAction openInNewTab
        else
          # If the user types something and hits enter without selecting a completion from the list, then try
          # to open their query as a URL directly. If it doesn't look like a URL, then use the default search
          # engine.
          @hide ->
            chrome.runtime.sendMessage
              handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
              url: query
      else
        completion = @completions[@selection]
        @hide -> completion.performAction openInNewTab
    else if action == "delete"
      if @suppressedLeadingKeyword? and @input.value.length == 0
        @input.value = @suppressedLeadingKeyword
        @suppressedLeadingKeyword = null
        @updateCompletions()
      else
        # Don't suppress the Delete.  We want it to happen.
        return true

    # It seems like we have to manually suppress the event here and still return true.
    event.stopImmediatePropagation()
    event.preventDefault()
    true

  # Test whether the input contains selected text.
  inputContainsASelectionRange: ->
    @input.selectionStart? and @input.selectionEnd? and @input.selectionStart != @input.selectionEnd

  # Return the text of the input, with any selected text renage removed.
  getInputWithoutSelectionRange: ->
    if @inputContainsASelectionRange()
      @input.value[0...@input.selectionStart] + @input.value[@input.selectionEnd..]
    else
      @input.value

  # Return the background-page query corresponding to the current input state.  In other words, reinstate any
  # custom search engine keyword which is currently stripped from the input.
  getInputValueAsQuery: ->
    (if @suppressedLeadingKeyword? then @suppressedLeadingKeyword + " " else "") + @input.value

  updateCompletions: (callback = null) ->
    @completer.filter @getInputValueAsQuery(), (response) =>
      { results, mayCacheResults } = response
      @completions = results
      # Update completion list with the new suggestions.
      @completionList.innerHTML = @completions.map((completion) -> "<li>#{completion.html}</li>").join("")
      @completionList.style.display = if @completions.length > 0 then "block" else ""
      @selection = Math.min @completions.length - 1, Math.max @initialSelectionValue, @selection
      @previousAutoSelect = null if @completions[0]?.autoSelect and @completions[0]?.forceAutoSelect
      @updateSelection()
      @highlightCommonMatches response
      callback?()

  updateOnInput: =>
    @completer.cancel()
    # If the user types, then don't reset any previous text, and re-enable auto-select.
    if @previousInputValue?
      @previousInputValue = null
      @previousAutoSelect = null
      @selection = -1
    @update false

  clearUpdateTimer: ->
    if @updateTimer?
      window.clearTimeout @updateTimer
      @updateTimer = null

  isCustomSearch: ->
    queryTerms = @input.value.ltrim().split /\s+/
    1 < queryTerms.length and queryTerms[0] in @keywords

  update: (updateSynchronously = false, callback = null) =>
    # If the query text becomes a custom search, then we need to force a synchronous update (so that the
    # interface is snappy).
    updateSynchronously ||= @isCustomSearch() and not @suppressedLeadingKeyword?
    if updateSynchronously
      @clearUpdateTimer()
      @updateCompletions callback
    else if not @updateTimer?
      # Update asynchronously for better user experience and to take some load off the CPU (not every
      # keystroke will cause a dedicated update)
      @updateTimer = Utils.setTimeout @refreshInterval, =>
        @updateTimer = null
        @updateCompletions callback

    @input.focus()

  initDom: ->
    @box = document.getElementById("vomnibar")

    @input = @box.querySelector("input")
    @input.addEventListener "input", @updateOnInput
    @input.addEventListener "keydown", @onKeydown
    @completionList = @box.querySelector("ul")
    @completionList.style.display = ""

    window.addEventListener "focus", => @input.focus()
    # A click in the vomnibar itself refocuses the input.
    @box.addEventListener "click", (event) =>
      @input.focus()
      event.stopImmediatePropagation()
    # A click anywhere else hides the vomnibar.
    document.body.addEventListener "click", => @hide()

#
# Sends requests to a Vomnibox completer on the background page.
#
class BackgroundCompleter
  debug: true

  # name is background-page completer to connect to: "omni", "tabs", or "bookmarks".
  constructor: (@name) ->
    @port = chrome.runtime.connect name: "completions"
    @messageId = null
    # @keywords and @cache are both reset in @reset().
    # We only cache for the duration of a single vomnibar activation.
    @keywords = []
    @cache = {}
    @reset()

    @port.onMessage.addListener (msg) =>
      switch msg.handler
        when "keywords"
          @keywords = msg.keywords
          @lastUI.setKeywords @keywords
        when "completions"
          # The result objects coming from the background page will be of the form:
          #   { html: "", type: "", url: "" }
          # Type will be one of [tab, bookmark, history, domain, search], or a custom search engine description.
          for result in msg.results
            result.performAction =
              if result.type == "tab"
                @completionActions.switchToTab.curry result.tabId
              else
                @completionActions.navigateToUrl.curry result.url

          # Cache the result -- if we have been told it's ok to do so (it could be that more results will be
          # posted shortly).  We cache the result even if it arrives late.
          if msg.mayCacheResults
            console.log "cache set:", "-#{msg.cacheKey}-" if @debug
            @cache[msg.cacheKey] = msg
          else
            console.log "not setting cache:", "-#{msg.cacheKey}-" if @debug

          # Handle the message, but only if it hasn't arrived too late.
          @mostRecentCallback msg if msg.id == @messageId

  filter: (query, @mostRecentCallback) ->
    queryTerms = query.trim().split(/\s+/).filter (s) -> 0 < s.length
    cacheKey = queryTerms.join " "
    cacheKey += " " if 0 < queryTerms.length and queryTerms[0] in @keywords and /\s$/.test query

    if cacheKey of @cache
      console.log "cache hit:", "-#{cacheKey}-" if @debug
      @mostRecentCallback @cache[cacheKey]
    else
      console.log "cache miss:", "-#{cacheKey}-" if @debug
      @port.postMessage
        handler: "filter"
        name: @name
        id: @messageId = Utils.createUniqueId()
        queryTerms: queryTerms
        query: query
        cacheKey: cacheKey

  reset: ->
    @keywords = []
    @cache = {}

  refresh: (@lastUI) ->
    @reset()
    # Inform the background completer that we have a new vomnibar activation.
    @port.postMessage name: @name, handler: "refresh"

  cancel: ->
    # Inform the background completer that it may (should it choose to do so) abandon any pending query
    # (because the user is typing, and there'll be another query along soon).
    @port.postMessage name: @name, handler: "cancel"

  # These are the actions we can perform when the user selects a result.
  completionActions:
    navigateToUrl: (url, openInNewTab) ->
      # If the URL is a bookmarklet (so, prefixed with "javascript:"), then we always open it in the current
      # tab.
      openInNewTab &&= not Utils.hasJavascriptPrefix url
      chrome.runtime.sendMessage
        handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
        url: url
        selected: openInNewTab

    switchToTab: (tabId) ->
      chrome.runtime.sendMessage handler: "selectSpecificTab", id: tabId

UIComponentServer.registerHandler (event) ->
  switch event.data
    when "hide" then Vomnibar.hide()
    when "hidden" then Vomnibar.onHidden()
    else Vomnibar.activate event.data

root = exports ? window
root.Vomnibar = Vomnibar

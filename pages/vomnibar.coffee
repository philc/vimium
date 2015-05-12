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
    extend options, refreshInterval: if options.completer == "omni" then 150 else 0

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
    @completer?.reset()

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

    # For suggestions for custom search engines, we copy the suggested text into the input when the item is
    # selected, and revert when it is not.  This allows the user to select a suggestion and then continue
    # typing.
    if 0 <= @selection and @completions[@selection].insertText?
      @previousInputValue ?=
        value: @input.value
        selectionStart: @input.selectionStart
        selectionEnd: @input.selectionEnd
      @input.value = @completions[@selection].insertText + (if @selection == 0 then "" else " ")
    else if @previousInputValue?
      # Restore the text.
      @input.value = @previousInputValue.value
      # Restore the selection.
      if @previousInputValue.selectionStart? and @previousInputValue.selectionEnd? and
        @previousInputValue.selectionStart != @previousInputValue.selectionEnd
          @input.setSelectionRange @previousInputValue.selectionStart, @previousInputValue.selectionEnd
      @previousInputValue = null

    # Highlight the selected entry, and only the selected entry.
    for i in [0...@completionList.children.length]
      @completionList.children[i].className = (if i == @selection then "vomnibarSelected" else "")

  # This adds prompted text to the vomnibar input.  The prompted text is a continuation of the text the user
  # has already typed, taken from one of the search suggestions.  It is highlight (using the selection) and
  # will be included with the query should the user type <Enter>.
  addPromptedText: (response) ->
    # Bail if we don't yet have the background completer's final word on the current query.
    return unless response.mayCacheResults

    value = @getInputWithoutPromptedText()
    @previousLength ?= value.length
    previousLength = @previousLength
    currentLength = value.length
    @previousLength = currentLength

    return unless previousLength < currentLength
    return if /^\s/.test(value) or /\s\s/.test value

    # Bail if there's an update pending (because then @input and the completion state are out of sync).
    return if @updateTimer?

    completions = @completions.filter (completion) -> completion.searchEngineCompletionSuggestion
    return unless 0 < completions.length

    query = value.ltrim().split(/\s+/).join(" ").toLowerCase()
    suggestion = completions[0].title

    index = suggestion.toLowerCase().indexOf query
    return unless 0 <= index and index + query.length < suggestion.length

    # If the typed text is all lower case, then make the prompted text lower case too.
    suggestion = suggestion[index..]
    suggestion = suggestion.toLowerCase() unless /[A-Z]/.test @getInputWithoutPromptedText()

    suggestion = suggestion[query.length..]
    @input.value = query + suggestion
    @input.setSelectionRange query.length, query.length + suggestion.length

  # Returns the user's action ("up", "down", "tab", etc, or null) based on their keypress.  We support the
  # arrow keys and various other shortcuts, and this function hides the event-decoding complexity.
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
    else if key in [ "left", "right" ]
      return key

    null

  onKeydown: (event) =>
    action = @actionFromKeyEvent(event)
    return true unless action # pass through

    openInNewTab = @forceNewTab ||
      (event.shiftKey || event.ctrlKey || KeyboardUtils.isPrimaryModifierKey(event))
    if (action == "dismiss")
      @hide()
    else if action in [ "tab", "down" ]
      @selection += 1
      @selection = @initialSelectionValue if @selection == @completions.length
      @updateSelection()
    else if (action == "up")
      @selection -= 1
      @selection = @completions.length - 1 if @selection < @initialSelectionValue
      @updateSelection()
    else if (action == "enter")
      if @selection == -1
        # <Alt>/<Meta> includes prompted text in the query (normally it is not included).
        #
        # FIXME(smblott).  This is a terrible binding. <Ctrl-Enter> would be better, but that's already being
        # used.  We need a better UX around how to include the prompted text in the query. <Right> then
        # <Enter> works, but that's ugly too.
        window.getSelection().collapseToEnd() if event.altKey or event.metaKey
        # The user has not selected a suggestion.
        query = @getInputWithoutPromptedText().trim()
        # <Enter> on an empty vomnibar is a no-op.
        return unless 0 < query.length
        if @suppressedLeadingKeyword?
          # This is a custom search engine completion.  The text in the input might not correspond to any of
          # the completions.  So we fire off the query to the background page and use the completion at the
          # top of the list (which will be the right one).
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
        # Normally, with custom search engines, the keyword (e,g, the "w" of "w query terms") is suppressed.
        # If the input is empty, then show the keyword again.
        @input.value = @suppressedLeadingKeyword
        @suppressedLeadingKeyword = null
        @updateCompletions()
      else
        return true # Do not suppress event.
    else if action in [ "left", "right" ]
      [ start, end ] = [ @input.selectionStart, @input.selectionEnd ]
      @previousLength = end
      if event.ctrlKey and not (event.altKey or event.metaKey)
        return true unless @inputContainsASelectionRange() and end == @input.value.length
        # "Control-Right" advances the start of the selection by a word.
        text = @input.value[start...end]
        switch action
          when "right"
            newText = text.replace /^\s*\S+\s*/, ""
            @input.setSelectionRange start + (text.length - newText.length), end
          when "left"
            newText = text.replace /\S+\s*$/, ""
            @input.setSelectionRange start + (newText.length - text.length), end
      else
        return true # Do not suppress event.

    # It seems like we have to manually suppress the event here and still return true.
    event.stopImmediatePropagation()
    event.preventDefault()
    true

  onKeypress: (event) =>
    # Handle typing together with prompted text.
    unless event.altKey or event.ctrlKey or event.metaKey
      if @inputContainsASelectionRange()
        # As the user types characters which the match the prompted text, we suppress the keyboard event and
        # simulate it by advancing the start of the selection (but only if the typed character matches).
        # If we were to allow the event through, we would get flicker, as the selection is first collapsed and
        # then (shortly afterwards) restored.
        if @input.value[@input.selectionStart][0].toLowerCase() == (String.fromCharCode event.charCode).toLowerCase()
          @input.setSelectionRange @input.selectionStart + 1, @input.selectionEnd
          @updateOnInput()
          event.stopImmediatePropagation()
          event.preventDefault()
    true

  # Test whether the input contains prompted text.
  inputContainsASelectionRange: ->
    @input.selectionStart? and @input.selectionEnd? and @input.selectionStart != @input.selectionEnd

  # Return the text of the input, with any prompted text removed.
  getInputWithoutPromptedText: ->
    if @inputContainsASelectionRange()
      @input.value[0...@input.selectionStart] + @input.value[@input.selectionEnd..]
    else
      @input.value

  # Return the background-page query corresponding to the current input state.  In other words, reinstate any
  # search engine keyword which is currently being suppressed, and strip any prompted text.
  getInputValueAsQuery: ->
    (if @suppressedLeadingKeyword? then @suppressedLeadingKeyword + " " else "") + @getInputWithoutPromptedText()

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
      @addPromptedText response
      callback?()

  updateOnInput: =>
    @completer.cancel()
    # If the user types, then don't reset any previous text, and restart auto select.
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
    # If the query text becomes a custom search (the user enters a search keyword), then we need to force a
    # synchronous update (so that the state is updated immediately).
    updateSynchronously ||= @isCustomSearch() and not @suppressedLeadingKeyword?
    if updateSynchronously
      @clearUpdateTimer()
      @updateCompletions callback
    else if not @updateTimer?
      # Update asynchronously for a better user experience, and to take some load off the CPU (not every
      # keystroke will cause a dedicated update).
      @updateTimer = Utils.setTimeout @refreshInterval, =>
        @updateTimer = null
        @updateCompletions callback

    @input.focus()

  initDom: ->
    @box = document.getElementById("vomnibar")

    @input = @box.querySelector("input")
    @input.addEventListener "input", @updateOnInput
    @input.addEventListener "keydown", @onKeydown
    @input.addEventListener "keypress", @onKeypress
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
  debug: false

  # The "name" is the background-page completer to connect to: "omni", "tabs", or "bookmarks".
  constructor: (@name) ->
    @port = chrome.runtime.connect name: "completions"
    @messageId = null
    @reset()

    @port.onMessage.addListener (msg) =>
      switch msg.handler
        when "keywords"
          @keywords = msg.keywords
          @lastUI.setKeywords @keywords
        when "completions"
          # The result objects coming from the background page will be of the form:
          #   { html: "", type: "", url: "", ... }
          # Type will be one of [tab, bookmark, history, domain, search], or a custom search engine description.
          for result in msg.results
            extend result,
              performAction:
                if result.type == "tab"
                  @completionActions.switchToTab result.tabId
                else
                  @completionActions.navigateToUrl result.url

          # Cache the results, but only if we have been told it's ok to do so (it could be that more results
          # will be posted shortly).  We cache the results even if they arrive late.
          if msg.mayCacheResults
            console.log "cache set:", "-#{msg.cacheKey}-" if @debug
            @cache[msg.cacheKey] = msg
          else
            console.log "not setting cache:", "-#{msg.cacheKey}-" if @debug

          # Handle the message, but only if it hasn't arrived too late.
          @mostRecentCallback msg if msg.id == @messageId

  filter: (query, @mostRecentCallback) ->
    cacheKey = query.ltrim().split(/\s+/).join " "

    if cacheKey of @cache
      console.log "cache hit:", "-#{cacheKey}-" if @debug
      @mostRecentCallback @cache[cacheKey]
    else
      console.log "cache miss:", "-#{cacheKey}-" if @debug
      @port.postMessage
        handler: "filter"
        name: @name
        id: @messageId = Utils.createUniqueId()
        queryTerms: query.trim().split(/\s+/).filter (s) -> 0 < s.length
        query: query
        cacheKey: cacheKey

  reset: ->
    [ @keywords, @cache ] = [ [], {} ]

  refresh: (@lastUI) ->
    @reset()
    @port.postMessage name: @name, handler: "refresh"

  cancel: ->
    # Inform the background completer that it may (should it choose to do so) abandon any pending query
    # (because the user is typing, and there will be another query along soon).
    @port.postMessage name: @name, handler: "cancel"

  # These are the actions we can perform when the user selects a result.
  completionActions:
    navigateToUrl: (url) -> (openInNewTab) ->
      # If the URL is a bookmarklet (so, prefixed with "javascript:"), then we always open it in the current
      # tab.
      openInNewTab &&= not Utils.hasJavascriptPrefix url
      chrome.runtime.sendMessage
        handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
        url: url
        selected: openInNewTab

    switchToTab: (tabId) -> ->
      chrome.runtime.sendMessage handler: "selectSpecificTab", id: tabId

UIComponentServer.registerHandler (event) ->
  switch event.data
    when "hide" then Vomnibar.hide()
    when "hidden" then Vomnibar.onHidden()
    else Vomnibar.activate event.data

root = exports ? window
root.Vomnibar = Vomnibar

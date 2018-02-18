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
      keyword: null
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
    @vomnibarUI.setKeyword options.keyword
    @vomnibarUI.update true

  hide: -> @vomnibarUI?.hide()
  onHidden: -> @vomnibarUI?.onHidden()

class VomnibarUI
  constructor: ->
    @refreshInterval = 0
    @onHiddenCallback = null
    @initDom()

  setQuery: (query) -> @input.value = query
  setKeyword: (keyword) -> @customSearchMode = keyword
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
  hide: (@onHiddenCallback = null) ->
    @input.blur()
    UIComponentServer.postMessage "hide"
    @reset()

  onHidden: ->
    @onHiddenCallback?()
    @onHiddenCallback = null
    @reset()

  reset: ->
    @clearUpdateTimer()
    @completionList.style.display = ""
    @input.value = ""
    @completions = []
    @previousInputValue = null
    @customSearchMode = null
    @selection = @initialSelectionValue
    @keywords = []
    @seenTabToOpenCompletionList = false
    @completer?.reset()

  updateSelection: ->
    # For custom search engines, we suppress the leading term (e.g. the "w" of "w query terms") within the
    # vomnibar input.
    if @lastReponse.isCustomSearch and not @customSearchMode?
      queryTerms = @input.value.trim().split /\s+/
      @customSearchMode = queryTerms[0]
      @input.value = queryTerms[1..].join " "

    # For suggestions for custom search engines, we copy the suggested text into the input when the item is
    # selected, and revert when it is not.  This allows the user to select a suggestion and then continue
    # typing.
    if 0 <= @selection and @completions[@selection].insertText?
      @previousInputValue ?= @input.value
      @input.value = @completions[@selection].insertText
    else if @previousInputValue?
      @input.value = @previousInputValue
      @previousInputValue = null

    # Highlight the selected entry, and only the selected entry.
    for i in [0...@completionList.children.length]
      @completionList.children[i].className = (if i == @selection then "vomnibarSelected" else "")

  # Returns the user's action ("up", "down", "tab", etc, or null) based on their keypress.  We support the
  # arrow keys and various other shortcuts, and this function hides the event-decoding complexity.
  actionFromKeyEvent: (event) ->
    key = KeyboardUtils.getKeyChar(event)
    # Handle <Enter> on "keypress", and other events on "keydown"; this avoids interence with CJK translation
    # (see #2915 and #2934).
    return null if event.type == "keypress" and key != "enter"
    return null if event.type == "keydown" and key == "enter"
    if (KeyboardUtils.isEscape(event))
      return "dismiss"
    else if (key == "up" ||
        (event.shiftKey && event.key == "Tab") ||
        (event.ctrlKey && (key == "k" || key == "p")))
      return "up"
    else if (event.key == "Tab" && !event.shiftKey)
      return "tab"
    else if (key == "down" ||
        (event.ctrlKey && (key == "j" || key == "n")))
      return "down"
    else if (event.key == "Enter")
      return "enter"
    else if KeyboardUtils.isBackspace event
      return "delete"

    null

  onKeyEvent: (event) =>
    @lastAction = action = @actionFromKeyEvent event
    return true unless action # pass through

    openInNewTab = @forceNewTab || event.shiftKey || event.ctrlKey || event.altKey || event.metaKey
    if (action == "dismiss")
      @hide()
    else if action in [ "tab", "down" ]
      if action == "tab" and
        @completer.name == "omni" and
        not @seenTabToOpenCompletionList and
        @input.value.trim().length == 0
          @seenTabToOpenCompletionList = true
          @update true
      else if 0 < @completions.length
        @selection += 1
        @selection = @initialSelectionValue if @selection == @completions.length
        @updateSelection()
    else if (action == "up")
      @selection -= 1
      @selection = @completions.length - 1 if @selection < @initialSelectionValue
      @updateSelection()
    else if (action == "enter")
      isCustomSearchPrimarySuggestion = @completions[@selection]?.isPrimarySuggestion and @lastReponse.engine?.searchUrl?
      if @selection == -1 or isCustomSearchPrimarySuggestion
        query = @input.value.trim()
        # <Enter> on an empty query is a no-op.
        return unless 0 < query.length
        # First case (@selection == -1).
        # If the user types something and hits enter without selecting a completion from the list, then:
        #   - If a search URL has been provided, then use it.  This is custom search engine request.
        #   - Otherwise, send the query to the background page, which will open it as a URL or create a
        #     default search, as appropriate.
        #
        # Second case (isCustomSearchPrimarySuggestion).
        # Alternatively, the selected completion could be the primary selection for a custom search engine.
        # Because the the suggestions are updated asynchronously in omni mode, the user may have typed more
        # text than that which is included in the URL associated with the primary suggestion.  Therefore, to
        # avoid a race condition, we construct the query from the actual contents of the input (query).
        query = Utils.createSearchUrl query, @lastReponse.engine.searchUrl if isCustomSearchPrimarySuggestion
        @hide -> Vomnibar.getCompleter().launchUrl query, openInNewTab
      else
        completion = @completions[@selection]
        @hide -> completion.performAction openInNewTab
    else if action == "delete"
      if @customSearchMode? and @input.selectionEnd == 0
        # Normally, with custom search engines, the keyword (e,g, the "w" of "w query terms") is suppressed.
        # If the cursor is at the start of the input, then reinstate the keyword (the "w").
        @input.value = @customSearchMode + @input.value.ltrim()
        @input.selectionStart = @input.selectionEnd = @customSearchMode.length
        @customSearchMode = null
        @update true
      else if @seenTabToOpenCompletionList and @input.value.trim().length == 0
        @seenTabToOpenCompletionList = false
        @update true
      else
        return true # Do not suppress event.

    # It seems like we have to manually suppress the event here and still return true.
    event.stopImmediatePropagation()
    event.preventDefault()
    true

  # Return the background-page query corresponding to the current input state.  In other words, reinstate any
  # search engine keyword which is currently being suppressed, and strip any prompted text.
  getInputValueAsQuery: ->
    (if @customSearchMode? then @customSearchMode + " " else "") + @input.value

  updateCompletions: (callback = null) ->
    @completer.filter
      query: @getInputValueAsQuery()
      seenTabToOpenCompletionList: @seenTabToOpenCompletionList
      callback: (@lastReponse) =>
        { results } = @lastReponse
        @completions = results
        @selection = if @completions[0]?.autoSelect then 0 else @initialSelectionValue
        # Update completion list with the new suggestions.
        @completionList.innerHTML = @completions.map((completion) -> "<li>#{completion.html}</li>").join("")
        @completionList.style.display = if @completions.length > 0 then "block" else ""
        @selection = Math.min @completions.length - 1, Math.max @initialSelectionValue, @selection
        @updateSelection()
        callback?()

  onInput: =>
    @seenTabToOpenCompletionList = false
    @completer.cancel()
    if 0 <= @selection and @completions[@selection].customSearchMode and not @customSearchMode
      @customSearchMode = @completions[@selection].customSearchMode
      updateSynchronously = true
    # If the user types, then don't reset any previous text, and reset the selection.
    if @previousInputValue?
      @previousInputValue = null
      @selection = -1
    @update updateSynchronously

  clearUpdateTimer: ->
    if @updateTimer?
      window.clearTimeout @updateTimer
      @updateTimer = null

  shouldActivateCustomSearchMode: ->
    queryTerms = @input.value.ltrim().split /\s+/
    1 < queryTerms.length and queryTerms[0] in @keywords and not @customSearchMode

  update: (updateSynchronously = false, callback = null) =>
    # If the query text becomes a custom search (the user enters a search keyword), then we need to force a
    # synchronous update (so that the state is updated immediately).
    updateSynchronously ||= @shouldActivateCustomSearchMode()
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
    @input.addEventListener "input", @onInput
    @input.addEventListener "keydown", @onKeyEvent
    @input.addEventListener "keypress", @onKeyEvent
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
          if msg.id == @messageId
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

            # Handle the message, but only if it hasn't arrived too late.
            @mostRecentCallback msg

  filter: (request) ->
    { query, callback } = request
    @mostRecentCallback = callback

    @port.postMessage extend request,
      handler: "filter"
      name: @name
      id: @messageId = Utils.createUniqueId()
      queryTerms: query.trim().split(/\s+/).filter (s) -> 0 < s.length
      # We don't send these keys.
      callback: null

  reset: ->
    @keywords = []

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
      Vomnibar.getCompleter().launchUrl url, openInNewTab

    switchToTab: (tabId) -> ->
      chrome.runtime.sendMessage handler: "selectSpecificTab", id: tabId

  launchUrl: (url, openInNewTab) ->
    # If the URL is a bookmarklet (so, prefixed with "javascript:"), then we always open it in the current
    # tab.
    openInNewTab &&= not Utils.hasJavascriptPrefix url
    chrome.runtime.sendMessage
      handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
      url: url

UIComponentServer.registerHandler (event) ->
  switch event.data.name ? event.data
    when "hide" then Vomnibar.hide()
    when "hidden" then Vomnibar.onHidden()
    when "activate" then Vomnibar.activate event.data

document.addEventListener "DOMContentLoaded", ->
  DomUtils.injectUserCss() # Manually inject custom user styles.

root = exports ? window
root.Vomnibar = Vomnibar

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
    @customSearchMode = null
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
    if @lastReponse.customSearchMode and not @customSearchMode?
      queryTerms = @input.value.trim().split /\s+/
      @customSearchMode = queryTerms[0]
      @input.value = queryTerms[1..].join " "

    # For suggestions for custom search engines, we copy the suggested text into the input when the item is
    # selected, and revert when it is not.  This allows the user to select a suggestion and then continue
    # typing.
    if 0 <= @selection and @completions[@selection].insertText?
      @previousInputValue ?= @input.value
      @input.value = @completions[@selection].insertText + (if @selection == 0 then "" else " ")
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
    @lastAction = action = @actionFromKeyEvent event
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
        query = @input.value.trim()
        # <Enter> on an empty query is a no-op.
        return unless 0 < query.length
        # If the user types something and hits enter without selecting a completion from the list, then:
        #   - If a search URL has been provided, then use it.  This is custom search engine request.
        #   - Otherwise, send the query to the background page, which will open it as a URL or create a
        #     default search, as appropriate.
        query = Utils.createSearchUrl query, @lastReponse.searchUrl if @lastReponse.searchUrl?
        @hide ->
          chrome.runtime.sendMessage
            handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
            url: query
      else
        completion = @completions[@selection]
        @hide -> completion.performAction openInNewTab
    else if action == "delete"
      if @customSearchMode? and @input.value.length == 0
        # Normally, with custom search engines, the keyword (e,g, the "w" of "w query terms") is suppressed.
        # If the input is empty, then reinstate the keyword (the "w").
        @input.value = @customSearchMode
        @customSearchMode = null
        @updateCompletions()
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
      callback: (@lastReponse) =>
        { results } = @lastReponse
        @completions = results
        # Update completion list with the new suggestions.
        @completionList.innerHTML = @completions.map((completion) -> "<li>#{completion.html}</li>").join("")
        @completionList.style.display = if @completions.length > 0 then "block" else ""
        @selection = Math.min @completions.length - 1, Math.max @initialSelectionValue, @selection
        @previousAutoSelect = null if @completions[0]?.autoSelect and @completions[0]?.forceAutoSelect
        @updateSelection()
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
    updateSynchronously ||= @isCustomSearch() and not @customSearchMode?
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
      mayUseVomnibarCache: null

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

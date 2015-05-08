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
    completer.refresh()
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
    @suppressedLeadingQueryTerm = null
    @selection = @initialSelectionValue

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
    if @suppressedLeadingQueryTerm?
      @restoreSuppressedQueryTerm()
    else if @completions[0]?.suppressLeadingQueryTerm
      # We've been asked to suppress the leading query term, and it's not already suppressed.  So suppress it.
      queryTerms = @input.value.trim().split /\s+/
      @suppressedLeadingQueryTerm = queryTerms[0]
      @input.value = queryTerms[1..].join " "

    # For suggestions from search-engine completion, we copy the suggested text into the input when selected,
    # and revert when not.  This allows the user to select a suggestion and then continue typing.
    if 0 <= @selection and @completions[@selection].insertText?
      @previousInputValue ?= @input.value
      @input.value = @completions[@selection].insertText + " "
    else if @previousInputValue?
        @input.value = @previousInputValue
        @previousInputValue = null

    # Highlight the the selected entry, and only the selected entry.
    for i in [0...@completionList.children.length]
      @completionList.children[i].className = (if i == @selection then "vomnibarSelected" else "")

  restoreSuppressedQueryTerm: ->
    if @suppressedLeadingQueryTerm?
      # If we have a suppressed term and the input is empty, then reinstate it.
      if @input.value.length == 0
        @input.value = @suppressedLeadingQueryTerm
        @suppressedLeadingQueryTerm = null

  #
  # Returns the user's action ("up", "down", "enter", "dismiss", "delete" or null) based on their keypress.
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
    else if (key == "down" ||
        (event.keyCode == keyCodes.tab && !event.shiftKey) ||
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
    else if (action == "up")
      @selection -= 1
      @selection = @completions.length - 1 if @selection < @initialSelectionValue
      @updateSelection()
    else if (action == "down")
      @selection += 1
      @selection = @initialSelectionValue if @selection == @completions.length
      @updateSelection()
    else if (action == "enter")
      # If they type something and hit enter without selecting a completion from our list of suggestions,
      # try to open their query as a URL directly. If it doesn't look like a URL, we will search using
      # google.
      if (@selection == -1)
        query = @input.value.trim()
        # <Enter> on an empty vomnibar is a no-op.
        return unless 0 < query.length
        @hide ->
          chrome.runtime.sendMessage
            handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
            url: query
      else
        completion = @completions[@selection]
        @hide -> completion.performAction openInNewTab
    else if action == "delete"
      if @input.value.length == 0
        @restoreSuppressedQueryTerm()
        @updateCompletions()
      else
        # Don't suppress the Delete.  We want it to happen.
        return true

    # It seems like we have to manually suppress the event here and still return true.
    event.stopImmediatePropagation()
    event.preventDefault()
    true

  getInputValue: ->
    (if @suppressedLeadingQueryTerm? then @suppressedLeadingQueryTerm + " " else "") + @input.value

  updateCompletions: (callback = null) ->
    @clearUpdateTimer()
    @completer.filter @getInputValue(), (@completions) =>
      @populateUiWithCompletions @completions
      callback?()

  populateUiWithCompletions: (completions) ->
    # Update completion list with the new suggestions.
    @completionList.innerHTML = completions.map((completion) -> "<li>#{completion.html}</li>").join("")
    @completionList.style.display = if completions.length > 0 then "block" else ""
    @selection = Math.min completions.length - 1, Math.max @initialSelectionValue, @selection
    @previousAutoSelect = null if completions[0]?.autoSelect and completions[0]?.forceAutoSelect
    @updateSelection()

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

  update: (updateSynchronously = false, callback = null) =>
    if updateSynchronously
      @updateCompletions callback
    else if not @updateTimer?
      # Update asynchronously for better user experience and to take some load off the CPU (not every
      # keystroke will cause a dedicated update)
      @updateTimer = Utils.setTimeout @refreshInterval, => @updateCompletions callback

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
    @cache ?= new SimpleCache 1000 * 60 * 5
    @reset()

    @port.onMessage.addListener (msg) =>
      # The result objects coming from the background page will be of the form:
      #   { html: "", type: "", url: "" }
      # Type will be one of [tab, bookmark, history, domain, search], or a custom search engine description.
      for result in msg.results
        result.performAction =
          if result.type == "tab"
            @completionActions.switchToTab.curry result.tabId
          else
            @completionActions.navigateToUrl.curry result.url

      # Cache the results (but only if the background completer tells us that it's ok to do so).
      if msg.callerMayCacheResults
        console.log "cache set:", msg.query if @debug
        @cache.set msg.query, msg.results
      else
        console.log "not setting cache:", msg.query if @debug

      # We ignore messages which arrive too late.
      if msg.id == @messageId
        @mostRecentCallback msg.results

  filter: (query, @mostRecentCallback) ->
    # We retain trailing whitespace so that we can tell the difference between "w" and "w " (for custom search
    # engines).
    queryTerms = query.ltrim().split(/\s+/)
    query = queryTerms.join " "
    if @cache.has query
      console.log "cache hit:", query if @debug
      @mostRecentCallback @cache.get query
    else
      @messageId = Utils.createUniqueId()
      @port.postMessage
        name: @name
        handler: "filter"
        id: @messageId
        query: query
        queryTerms: queryTerms

  refresh: ->
    @reset()
    # Inform the background completer that we have a new vomnibar activation.
    @port.postMessage name: @name, handler: "refresh"

  reset: ->
    # We only cache results for the duration of a single vomnibar activation, so clear the cache now.
    @cache.clear()

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

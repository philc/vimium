Vomnibar =
  vomnibarUI: null # the dialog instance for this window
  completers: {}

  getCompleter: (name) ->
    unless name of @completers
      @completers[name] = new BackgroundCompleter(name)
    @completers[name]

  #
  # Activate the Vomnibox.
  #
  activateWithCompleter: (completerName, refreshInterval, initialQueryValue, selectFirstResult, forceNewTab) ->
    completer = @getCompleter(completerName)
    @vomnibarUI = new VomnibarUI() unless @vomnibarUI
    completer.refresh()
    @vomnibarUI.setInitialSelectionValue(if selectFirstResult then 0 else -1)
    @vomnibarUI.setCompleter(completer)
    @vomnibarUI.setRefreshInterval(refreshInterval)
    @vomnibarUI.setForceNewTab(forceNewTab)
    @vomnibarUI.show()
    if initialQueryValue
      @vomnibarUI.setQuery(initialQueryValue)
      @vomnibarUI.update()

  activate: -> @activateWithCompleter("omni", 100)
  activateInNewTab: -> @activateWithCompleter("omni", 100, null, false, true)
  activateTabSelection: -> @activateWithCompleter("tabs", 0, null, true)
  activateBookmarks: -> @activateWithCompleter("bookmarks", 0, null, true)
  activateBookmarksInNewTab: -> @activateWithCompleter("bookmarks", 0, null, true, true)
  getUI: -> @vomnibarUI


class VomnibarUI
  constructor: ->
    @refreshInterval = 0
    @initDom()

  setQuery: (query) -> @input.value = query

  setInitialSelectionValue: (initialSelectionValue) ->
    @initialSelectionValue = initialSelectionValue

  setCompleter: (completer) ->
    @completer = completer
    @reset()

  setRefreshInterval: (refreshInterval) -> @refreshInterval = refreshInterval

  setForceNewTab: (forceNewTab) -> @forceNewTab = forceNewTab

  show: ->
    @box.style.display = "block"
    @input.focus()
    @handlerId = handlerStack.push keydown: @onKeydown.bind this

  hide: ->
    @box.style.display = "none"
    @completionList.style.display = "none"
    @input.blur()
    handlerStack.remove @handlerId

  reset: ->
    @input.value = ""
    @updateTimer = null
    @completions = []
    @selection = @initialSelectionValue
    @update(true)

  updateSelection: ->
    for i in [0...@completionList.children.length]
      @completionList.children[i].className = if i is @selection then "vomnibarSelected" else ""

  #
  # Returns the user's action ("up", "down", "enter", "dismiss" or null) based on their keypress.
  # We support the arrow keys and other shortcuts for moving, so this method hides that complexity.
  #
  actionFromKeyEvent: (event) ->
    key = KeyboardUtils.getKeyChar(event)

    return "dismiss" if KeyboardUtils.isEscape(event)

    return "up" if key is "up" or
        (event.shiftKey and event.keyCode is keyCodes.tab) or
        (event.ctrlKey and (key is "k" or key is "p"))

    return "down" if key is "down" or
        (event.keyCode is keyCodes.tab and !event.shiftKey) or
        (event.ctrlKey and (key is "j" or key is "n"))

    return "enter" if event.keyCode is keyCodes.enter

  onKeydown: (event) ->
    action = @actionFromKeyEvent(event)
    return true unless action # pass through

    openInNewTab = @forceNewTab or
      (event.shiftKey or event.ctrlKey or KeyboardUtils.isPrimaryModifierKey(event))
    if action is "dismiss"
      @hide()
    else if action is "up"
      @selection -= 1
      @selection = @completions.length - 1 if @selection < @initialSelectionValue
      @updateSelection()
    else if action is "down"
      @selection += 1
      @selection = @initialSelectionValue if @selection is @completions.length
      @updateSelection()
    else if action is "enter"
      # If they type something and hit enter without selecting a completion from our list of suggestions,
      # try to open their query as a URL directly. If it doesn't look like a URL, we will search using
      # google.
      if @selection is -1
        query = @input.value.trim()
        # <Enter> on an empty vomnibar is a no-op.
        return unless 0 < query.length
        @hide()
        chrome.extension.sendMessage({
          handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
          url: query })
      else
        @update true, =>
          # Shift+Enter will open the result in a new tab instead of the current tab.
          @completions[@selection].performAction(openInNewTab)
          @hide()

    # It seems like we have to manually suppress the event here and still return true.
    event.stopPropagation()
    event.preventDefault()
    true

  updateCompletions: (callback) ->
    query = @input.value.trim()

    @completer.filter query, (@completions) =>
      @populateUiWithCompletions(@completions)
      callback?()

  populateUiWithCompletions: (completions) ->
    # update completion list with the new data
    @completionList.innerHTML = completions.map((completion) -> "<li>#{completion.html}</li>").join("")
    @completionList.style.display = if completions.length > 0 then "block" else "none"
    @selection = Math.min(Math.max(@initialSelectionValue, @selection), @completions.length - 1)
    @updateSelection()

  update: (updateSynchronously, callback) ->
    if updateSynchronously
      # cancel scheduled update
      window.clearTimeout(@updateTimer) unless @updateTimer is null
      @updateCompletions(callback)
    else unless @updateTimer is null
      # an update is already scheduled, don't do anything
      return
    else
      # always update asynchronously for better user experience and to take some load off the CPU
      # (not every keystroke will cause a dedicated update)
      @updateTimer = setTimeout(=>
        @updateCompletions(callback)
        @updateTimer = null
      @refreshInterval)

  initDom: ->
    @box = Utils.createElementFromHtml(
      """
      <div id="vomnibar" class="vimiumReset">
        <div class="vimiumReset vomnibarSearchArea">
          <input type="text" class="vimiumReset">
        </div>
        <ul class="vimiumReset"></ul>
      </div>
      """)
    @box.style.display = "none"
    document.body.appendChild(@box)

    @input = document.querySelector("#vomnibar input")
    @input.addEventListener "input", => @update()
    @completionList = document.querySelector("#vomnibar ul")
    @completionList.style.display = "none"

#
# Sends filter and refresh requests to a Vomnibox completer on the background page.
#
class BackgroundCompleter
  # - name: The background page completer that you want to interface with. Either "omni", "tabs", or
  # "bookmarks". */
  constructor: (@name) ->
    @filterPort = chrome.extension.connect({ name: "filterCompleter" })

  refresh: -> chrome.extension.sendMessage({ handler: "refreshCompleter", name: @name })

  filter: (query, callback) ->
    id = Utils.createUniqueId()
    @filterPort.onMessage.addListener (msg) ->
      return unless msg.id is id
      # The result objects coming from the background page will be of the form:
      #   { html: "", type: "", url: "" }
      # type will be one of [tab, bookmark, history, domain].
      results = msg.results.map (result) ->
        functionToCall = if result.type is "tab"
          BackgroundCompleter.completionActions.switchToTab.curry(result.tabId)
        else
          BackgroundCompleter.completionActions.navigateToUrl.curry(result.url)
        result.performAction = functionToCall
        result
      callback(results)

    @filterPort.postMessage({ id: id, name: @name, query: query })

extend BackgroundCompleter,
  #
  # These are the actions we can perform when the user selects a result in the Vomnibox.
  #
  completionActions:
    navigateToUrl: (url, openInNewTab) ->
      # If the URL is a bookmarklet prefixed with javascript:, we shouldn't open that in a new tab.
      if url.startsWith "javascript:"
        script = document.createElement 'script'
        script.textContent = decodeURIComponent(url["javascript:".length..])
        (document.head or document.documentElement).appendChild script
      else
        chrome.extension.sendMessage(
          handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
          url: url,
          selected: openInNewTab)

    switchToTab: (tabId) -> chrome.extension.sendMessage({ handler: "selectSpecificTab", id: tabId })

root = exports ? window
root.Vomnibar = Vomnibar

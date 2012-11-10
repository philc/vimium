Vomnibar =
  vomnibarUI: null # the dialog instance for this window
  completers: {}

  getCompleter: (name) ->
    if (!(name of @completers))
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
    if (initialQueryValue)
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
    @handlerId = handlerStack.push keydown: @onKeydown.bind @

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
      @completionList.children[i].className = (if i == @selection then "vomnibarSelected" else "")

  #
  # Returns the user's action ("up", "down", "enter", "dismiss" or null) based on their keypress.
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

  onKeydown: (event) ->
    action = @actionFromKeyEvent(event)
    return true unless action # pass through

    openInNewTab = @forceNewTab || (event.shiftKey || KeyboardUtils.isPrimaryModifierKey(event))
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
        @hide()
        chrome.extension.sendRequest({
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

    @completer.filter query, (completions) =>
      @completions = completions
      @populateUiWithCompletions(completions)
      callback() if callback

  populateUiWithCompletions: (completions) ->
    # update completion list with the new data
    @completionList.innerHTML = completions.map((completion) -> "<li>#{completion.html}</li>").join("")
    @completionList.style.display = if completions.length > 0 then "block" else "none"
    @selection = Math.min(Math.max(@initialSelectionValue, @selection), @completions.length - 1)
    @updateSelection()

  update: (updateSynchronously, callback) ->
    if (updateSynchronously)
      # cancel scheduled update
      if (@updateTimer != null)
        window.clearTimeout(@updateTimer)
      @updateCompletions(callback)
    else if (@updateTimer != null)
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

  refresh: -> chrome.extension.sendRequest({ handler: "refreshCompleter", name: @name })

  filter: (query, callback) ->
    id = Utils.createUniqueId()
    @filterPort.onMessage.addListener (msg) ->
      return if (msg.id != id)
      # The result objects coming from the background page will be of the form:
      #   { html: "", type: "", url: "" }
      # type will be one of [tab, bookmark, history, domain].
      results = msg.results.map (result) ->
        functionToCall = if (result.type == "tab")
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
        (document.head || document.documentElement).appendChild script
      else
        chrome.extension.sendRequest(
          handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
          url: url,
          selected: openInNewTab)

    switchToTab: (tabId) -> chrome.extension.sendRequest({ handler: "selectSpecificTab", id: tabId })

root = exports ? window
root.Vomnibar = Vomnibar

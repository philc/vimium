#
# This controls the contents of the Vomnibar iframe. We use an iframe to avoid changing the selection on the
# page (useful for bookmarklets), ensure that the Vomnibar style is unaffected by the page, and simplify key
# handling in vimium_frontend.coffee
#
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
  activateWithCompleter: (options) ->
    completer = @getCompleter(options.completer)
    @vomnibarUI ?= new VomnibarUI()
    completer.refresh()
    @vomnibarUI.setInitialSelectionValue(if options.selectFirst then 0 else -1)
    @vomnibarUI.setCompleter(completer)
    @vomnibarUI.setRefreshInterval(options.refreshInterval)
    @vomnibarUI.setForceNewTab(options.newTab)
    @vomnibarUI.setFrameId(options.frameId)
    @vomnibarUI.show()
    if (options.query)
      @vomnibarUI.setQuery(options.query)
      @vomnibarUI.update()

  activate: -> @activateWithCompleter {completer:"omni"}
  activateInNewTab: -> @activateWithCompleter {
    completer: "omni"
    selectFirst: false
    newTab: true
  }
  activateTabSelection: -> @activateWithCompleter {
    completer: "tabs"
    selectFirst: true
  }
  activateBookmarks: -> @activateWithCompleter {
    completer: "bookmarks"
    selectFirst: true
  }
  activateBookmarksInNewTab: -> @activateWithCompleter {
    completer: "bookmarks"
    selectFirst: true
    newTab: true
  }
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

  setFrameId: (frameId) -> @frameId = frameId

  show: ->
    @box.style.display = "block"
    @input.focus()
    @input.addEventListener "keydown", @onKeydown

    chrome.runtime.sendMessage
      handler: "echo"
      name: "vomnibarShow"
      frameId: @frameId

  hide: ->
    @box.style.display = "none"
    @completionList.style.display = "none"
    @input.blur()
    @input.removeEventListener "keydown", @onKeydown
    window.parent.focus()
    chrome.runtime.sendMessage
      handler: "echo"
      name: "vomnibarClose"
      frameId: @frameId

  reset: ->
    @input.value = ""
    @updateTimer = null
    @completions = []
    @selection = @initialSelectionValue
    @update(true)

  updateSelection: ->
    # We have taken the option to add some global state here (previousCompletionType) to tell if a search
    # item has just appeared or disappeared, if that happens we either set the initialSelectionValue to 0 or 1
    # I feel that this approach is cleaner than bubbling the state up from the suggestion level
    # so we just inspect it afterwards
    if @completions[0]
      if @previousCompletionType != "search" && @completions[0].type == "search"
        @selection = 0
      else if @previousCompletionType == "search" && @completions[0].type != "search"
        @selection = -1
    for i in [0...@completionList.children.length]
      @completionList.children[i].className = (if i == @selection then "vomnibarSelected" else "")
    @previousCompletionType = @completions[0].type if @completions[0]

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
        @hide()
        chrome.runtime.sendMessage({
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
    @box = document.getElementById("vomnibar")

    @input = @box.querySelector("input")
    @input.addEventListener "input", => @update()
    @completionList = @box.querySelector("ul")
    @completionList.style.display = "none"

    window.addEventListener "focus", => @input.focus()

#
# Sends filter and refresh requests to a Vomnibox completer on the background page.
#
class BackgroundCompleter
  # - name: The background page completer that you want to interface with. Either "omni", "tabs", or
  # "bookmarks". */
  constructor: (@name) ->
    @filterPort = chrome.runtime.connect({ name: "filterCompleter" })

  refresh: -> chrome.runtime.sendMessage({ handler: "refreshCompleter", name: @name })

  filter: (query, callback) ->
    id = Utils.createUniqueId()
    @filterPort.onMessage.addListener (msg) =>
      @filterPort.onMessage.removeListener(arguments.callee)
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
      openInNewTab = false if url.startsWith("javascript:")
      chrome.runtime.sendMessage(
        handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
        url: url,
        selected: openInNewTab)

    switchToTab: (tabId) -> chrome.runtime.sendMessage({ handler: "selectSpecificTab", id: tabId })

initializeOnDomReady = ->
  options =
    completer: "omni"
    query: null
    frameId: -1

  booleanOptions = ["selectFirst", "newTab"]

  # Convert options in URL to options object
  document.location.search
    .split(/[\?&]/)
    .map((option) ->
      [name, value] = option.split "="
      options[name] = value
    )

  # Set boolean options
  for option in booleanOptions
    options[option] = option of options and options[option] != "false"

  options.refreshInterval = switch options.completer
    when "omni" then 100
    else 0

  Vomnibar.activateWithCompleter options

window.addEventListener "DOMContentLoaded", initializeOnDomReady

root = exports ? window
root.Vomnibar = Vomnibar

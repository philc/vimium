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
  activateEditUrl: -> @activateWithCompleter("omni", 100, window.location.href)
  activateEditUrlInNewTab: -> @activateWithCompleter("omni", 100, window.location.href, false, true)
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

  onKeydown: (event) ->
    action = @actionFromKeyEvent(event)
    return true unless action # pass through

    openInNewTab = @forceNewTab ||
      (event.shiftKey || event.ctrlKey || KeyboardUtils.isPrimaryModifierKey(event))
    if (action == "dismiss")
      @hide()
    else if (action == "up")
      @selection -= 1
      @selection = @completions.length - 1 if @selection < @initialSelectionValue
      @input.value = @completions[@selection].url
      @updateSelection()
    else if (action == "down")
      @selection += 1
      @selection = @initialSelectionValue if @selection == @completions.length
      @input.value = @completions[@selection].url
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

  # Various ways in which we met get or guess the favicon for a suggestion.  Not all of these are currently
  # used.
  useKnownFaviconUrl: (favicon) -> favicon.getAttribute "favIconUrl"
  guessChromeFaviconUrl: (favicon) -> "chrome://favicon/http://" + favicon.getAttribute "domain"
  guessHttpFaviconUrl: (favicon) -> "http://" + favicon.getAttribute("domain") + "/favicon.ico"
  guessHttpsFaviconUrl: (favicon) -> "https://" + favicon.getAttribute("domain") + "/favicon.ico"
  guessGoogleFaviconUrl: (favicon) -> "https://www.google.com/profiles/c/favicons?domain="

  # Chrome and Google's default favicons; cached here for the benefit of their servers :-)
  chromeCacheMissFavicon: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAArklEQVR4XqWQQQqDQAxFf1zY21k3XsAeoHgYu7NasV5QqM5mUlACw5RMWvrh7T6Pn2TMjH/IEGSaJtYgIoRIQsFurKrqg2VZMI4jI04s8P7obJsTICmKM4bhIRJ9QSplWaLvB04s8ADiW4975/m5s64vdN2df1pQ15cQ6SkLojjnQqSnC4hgYAiOUAJbYCA9/YkW9hOJdOwFIOT5SQWg1AJG295MvFcETXOlbxHBG8Vy2fHIq9l6AAAAAElFTkSuQmCC"
  googleCacheMissFavicon: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAACXBIWXMAAAsSAAALEgHS3X78AAACiElEQVQ4EaVTzU8TURCf2tJuS7tQtlRb6UKBIkQwkRRSEzkQgyEc6lkOKgcOph78Y+CgjXjDs2i44FXY9AMTlQRUELZapVlouy3d7kKtb0Zr0MSLTvL2zb75eL838xtTvV6H/xELBptMJojeXLCXyobnyog4YhzXYvmCFi6qVSfaeRdXdrfaU1areV5KykmX06rcvzumjY/1ggkR3Jh+bNf1mr8v1D5bLuvR3qDgFbvbBJYIrE1mCIoCrKxsHuzK+Rzvsi29+6DEbTZz9unijEYI8ObBgXOzlcrx9OAlXyDYKUCzwwrDQx1wVDGg089Dt+gR3mxmhcUnaWeoxwMbm/vzDFzmDEKMMNhquRqduT1KwXiGt0vre6iSeAUHNDE0d26NBtAXY9BACQyjFusKuL2Ry+IPb/Y9ZglwuVscdHaknUChqLF/O4jn3V5dP4mhgRJgwSYm+gV0Oi3XrvYB30yvhGa7BS70eGFHPoTJyQHhMK+F0ZesRVVznvXw5Ixv7/C10moEo6OZXbWvlFAF9FVZDOqEABUMRIkMd8GnLwVWg9/RkJF9sA4oDfYQAuzzjqzwvnaRUFxn/X2ZlmGLXAE7AL52B4xHgqAUqrC1nSNuoJkQtLkdqReszz/9aRvq90NOKdOS1nch8TpL555WDp49f3uAMXhACRjD5j4ykuCtf5PP7Fm1b0DIsl/VHGezzP1KwOiZQobFF9YyjSRYQETRENSlVzI8iK9mWlzckpSSCQHVALmN9Az1euDho9Xo8vKGd2rqooA8yBcrwHgCqYR0kMkWci08t/R+W4ljDCanWTg9TJGwGNaNk3vYZ7VUdeKsYJGFNkfSzjXNrSX20s4/h6kB81/271ghG17l+rPTAAAAAElFTkSuQmCC"

  # Note(smblott)  In certain (unknown) circumstances, chrome serializes XMLHttpRequests to the same domain,
  # and doesn't cache the results.  The following is an asynchronous memo function which prevents us sending
  # off multiple XMLHttpRequests for the same URL.
  faviconCache: do ->
    cache = {}
    callbacks = {}
    (url,callback) ->
      if url of cache
        callback cache[url]
      else if url of callbacks
        callbacks[url].push callback
      else
        callbacks[url] = [ callback ]
        chrome.runtime.sendMessage {handler: "fetchViaHttpAsBase64", url: url}, (response) =>
          cache[url] = response
          for callback in callbacks[url]
            callback response

  guessFavicon: (favicon, guessers) ->
    if 0 < guessers.length
      url = guessers[0](favicon)
      tryNextGuess = => @guessFavicon favicon, guessers[1..]
      return tryNextGuess() unless url
      @faviconCache url, (response) =>
        if response.data and response.type and 0 == response.type.indexOf "image/"
          if response.data != @chromeCacheMissFavicon
            return favicon.src = response.data
        tryNextGuess()

  populateUiWithCompletions: (completions) ->
    # update completion list with the new data
    @completionList.innerHTML = completions.map((completion) -> "<li>#{completion.html}</li>").join("")
    @completionList.style.display = if completions.length > 0 then "block" else "none"
    @selection = Math.min(Math.max(@initialSelectionValue, @selection), @completions.length - 1)
    # activate favicon guessers
    for favicon in @completionList.getElementsByClassName "vomnibarIcon"
      favicon.src = @googleCacheMissFavicon
      # Strategy.  Use a known favicon URL, if we have one.  Then try chrome's favicon cache (but we only use
      # this favicon if it's not chrome's default favicon).  Then try guessing over HTTP.  If all of that
      # fails, we'll be left with Google's default favicon, which is a little globe (@googleCacheMissFavicon).
      @guessFavicon favicon, [@useKnownFaviconUrl, @guessChromeFaviconUrl, @guessHttpFaviconUrl]
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
      if url.startsWith "javascript:"
        script = document.createElement 'script'
        script.textContent = decodeURIComponent(url["javascript:".length..])
        (document.head || document.documentElement).appendChild script
      else
        chrome.runtime.sendMessage(
          handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
          url: url,
          selected: openInNewTab)

    switchToTab: (tabId) -> chrome.runtime.sendMessage({ handler: "selectSpecificTab", id: tabId })

root = exports ? window
root.Vomnibar = Vomnibar

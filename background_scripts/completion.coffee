class Suggestion
  showRelevancy: true # Set this to true to render relevancy when debugging the ranking scores.

  # - type: one of [bookmark, history, tab].
  constructor: (@queryTerms, @type, @url, @title, @computeRelevancyFunction, @extraRelevancyData) ->

  generateHtml: ->
    return @html if @html
    relevancyHtml = if @showRelevancy then "<span class='relevancy'>#{@computeRelevancy() + ''}</span>" else ""
    @html =
      "<div class='topHalf'>
         <span class='source'>#{@type}</span>
         <span class='title'>#{@highlightTerms(utils.escapeHtml(@title))}</span>
       </div>
       <div class='bottomHalf'>
        <span class='url'>#{@shortenUrl(@highlightTerms(@url))}</span>
        #{relevancyHtml}
      </div>"

  shortenUrl: (url) ->
    @stripTrailingSlash(url).replace(/^http:\/\//, "")

  stripTrailingSlash: (url) ->
    url = url.substring(url, url.length - 1) if url[url.length - 1] == "/"
    url

  # Wraps each occurence of the query terms in the given string in a <span>.
  highlightTerms: (string) ->
    toReplace = {}
    for term in @queryTerms
      regexp = @escapeRegexp(term)
      i = string.search(regexp)
      toReplace[i] = term.length if i >= 0 && (!toReplace[i] || toReplace[i].length < term.length)

    indices = []
    indices.push([key, toReplace[key]]) for key of toReplace
    indices.sort (a, b) -> b - a
    for [i, length] in indices
      i = +i # convert i from String to Integer.
      string =
        string.substr(0, i) +
        "<span class='match'>" + string.substr(i, length) + "</span>" +
        string.substr(i + length)
    string

  # Creates a Regexp from the given string, with all special Regexp characters escaped.
  escapeRegexp: (string) ->
    # Taken from http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
    Suggestion.escapeRegExp ||= /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g
    new RegExp(string.replace(Suggestion.escapeRegExp, "\\$&"), "i")

  computeRelevancy: -> @relevancy = @computeRelevancyFunction(@queryTerms, this)

class BookmarkCompleter
  currentSearch: null
  # These bookmarks are loaded asynchronously when refresh() is called.
  bookmarks: null

  filter: (@queryTerms, @onComplete) ->
    @currentSearch = { queryTerms: @queryTerms, onComplete: @onComplete }
    @performSearch() if @bookmarks

  onBookmarksLoaded: -> @performSearch() if @currentSearch

  performSearch: ->
    results = @bookmarks.filter (bookmark) =>
        RankingUtils.matches(@currentSearch.queryTerms, bookmark.url, bookmark.title)
    suggestions = results.map (bookmark) =>
      new Suggestion(@currentSearch.queryTerms, "bookmark", bookmark.url, bookmark.title, @computeRelevancy)
    onComplete = @currentSearch.onComplete
    @currentSearch = null
    onComplete(suggestions)

  refresh: ->
    @bookmarks = null
    chrome.bookmarks.getTree (bookmarks) =>
      @bookmarks = @traverseBookmarks(bookmarks).filter((bookmark) -> bookmark.url?)
      @onBookmarksLoaded()

  # Traverses the bookmark hierarchy, and retuns a flattened list of all bookmarks in the tree.
  traverseBookmarks: (bookmarks) ->
    results = []
    toVisit = bookmarks
    while toVisit.length > 0
      bookmark = toVisit.shift()
      results.push(bookmark)
      toVisit.push.apply(toVisit, bookmark.children) if (bookmark.children)
    results

  computeRelevancy: (queryTerms, suggestion) ->
    RankingUtils.wordRelevancy(queryTerms, suggestion.url, suggestion.title)

class HistoryCompleter
  filter: (queryTerms, onComplete) ->
    @currentSearch = { queryTerms: @queryTerms, onComplete: @onComplete }
    results = []
    HistoryCache.use (history) ->
      results = history.filter (entry) -> RankingUtils.matches(queryTerms, entry.url, entry.title)
    suggestions = results.map (entry) =>
      new Suggestion(queryTerms, "history", entry.url, entry.title, @computeRelevancy, entry)
    onComplete(suggestions)

  computeRelevancy: (queryTerms, suggestion) ->
    @oneMonthAgo ||= 1000 * 60 * 60 * 24 * 30
    historyEntry = suggestion.extraRelevancyData
    recency = Date.now() - historyEntry.lastVisitTime
    recencyDifference = Math.max(0, @oneMonthAgo - recency) / @oneMonthAgo

    # recencyScore is between [0, 1]. It is 1 when recenyDifference is 0. This qudratic equation will
    # incresingly discount older history entries.
    recencyScore = recencyDifference * recencyDifference * recencyDifference

    wordRelevancy = RankingUtils.wordRelevancy(queryTerms, suggestion.url, suggestion.title)
    # Average out the word score and the recency. Recency has the ability to pull the score up, but not down.
    score = (wordRelevancy + Math.max(recencyScore, wordRelevancy)) / 2

  refresh: ->

class MultiCompleter
  constructor: (@completers) ->
    @maxResults = 10 # TODO(philc): Should this be configurable?

  refresh: -> completer.refresh() for completer in @completers

  filter: (queryTerms, onComplete) ->
    suggestions = []
    completersFinished = 0
    for completer in @completers
      # Call filter() on every source completer and wait for them all to finish before returning results.
      completer.filter queryTerms, (newSuggestions) =>
        suggestions = suggestions.concat(newSuggestions)
        completersFinished += 1
        if completersFinished >= @completers.length
          results = @sortSuggestions(suggestions)[0...@maxResults]
          result.generateHtml() for result in results
          onComplete(results)

  sortSuggestions: (suggestions) ->
    for suggestion in suggestions
      suggestion.computeRelevancy(@queryTerms)
    suggestions.sort (a, b) -> b.relevancy - a.relevancy
    suggestions

RankingUtils =
  # Whether the given URL or title match any one of the query terms. This is used to prune out irrelevant
  # suggestions before we try to rank them.
  matches: (queryTerms, url, title) ->
    return false if queryTerms.length == 0
    for term in queryTerms
      return false unless title.indexOf(term) >= 0 || url.indexOf(term) >= 0
    true

  # Returns a number between [0, 1] indicating how often the query terms appear in the url and title.
  wordRelevancy: (queryTerms, url, title) ->
    queryLength = 0
    urlScore = 0.0
    titleScore = 0.0
    for term in queryTerms
      queryLength += term.length
      urlScore += 1 if url.indexOf(term) >= 0
      titleScore += 1 if title.indexOf(term) >= 0
    urlScore = urlScore / queryTerms.length
    urlScore = urlScore * RankingUtils.normalizeDifference(queryLength, url.length)
    titleScore = titleScore / queryTerms.length
    titleScore = titleScore * RankingUtils.normalizeDifference(queryLength, title.length)
    (urlScore + titleScore) / 2

  # Takes the difference of two numbers and returns a number between [0, 1] (the percentage difference).
  normalizeDifference: (a, b) ->
    max = Math.max(a, b)
    (max - Math.abs(a - b)) / max

# Provides cached access to Chrome's history.
HistoryCache =
  size: 20000
  history: null # An array of History items returned from Chrome.

  use: (callback) ->
    return @fetchHistory(callback) unless @history?
    callback(@history)

  fetchHistory: (callback) ->
    return @callbacks.push(callback) if @callbacks
    @callbacks = [callback]
    chrome.history.search { text: "", maxResults: @size, startTime: 0 }, (history) =>
      # sorting in ascending order. We will push new items on to the end as the user navigates to new pages.
      history.sort((a, b) -> (a.lastVisitTime || 0) - (b.lastVisitTime || 0))
      @history = history
      chrome.history.onVisited.addListener (newSite) =>
        firstTimeVisit = (newSite.visitedCount == 1)
        @history.push(newSite) if firstTimeVisit
      callback(@history) for callback in @callbacks
      @callbacks = null

root = exports ? window
root.Suggestion = Suggestion
root.BookmarkCompleter = BookmarkCompleter
root.MultiCompleter = MultiCompleter
root.HistoryCompleter = HistoryCompleter

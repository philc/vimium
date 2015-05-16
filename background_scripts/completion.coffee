# This file contains the definition of the completers used for the Vomnibox's suggestion UI. A completer will
# take a query (whatever the user typed into the Vomnibox) and return a list of Suggestions, e.g. bookmarks,
# domains, URLs from history.
#
# The Vomnibox frontend script makes a "filterCompleter" request to the background page, which in turn calls
# filter() on each these completers.
#
# A completer is a class which has three functions:
#  - filter(query, onComplete): "query" will be whatever the user typed into the Vomnibox.
#  - refresh(): (optional) refreshes the completer's data source (e.g. refetches the list of bookmarks).
#  - cancel(): (optional) cancels any pending, cancelable action.
class Suggestion
  showRelevancy: true # Set this to true to render relevancy when debugging the ranking scores.

  constructor: (@options) ->
    # Required options.
    @queryTerms = null
    @type = null
    @url = null
    @relevancyFunction = null
    # Other options.
    @title = ""
    # Extra data which will be available to the relevancy function.
    @relevancyData = null
    # If @autoSelect is truthy, then this suggestion is automatically pre-selected in the vomnibar.  There may
    # be at most one such suggestion.
    @autoSelect = false
    # If truthy (and @autoSelect is truthy too), then this suggestion is always pre-selected when the query
    # changes.  There may be at most one such suggestion.
    @forceAutoSelect = false
    # If @highlightTerms is true, then we highlight matched terms in the title and URL.
    @highlightTerms = true
    # If @insertText is a string, then the indicated text is inserted into the vomnibar input when the
    # suggestion is selected.
    @insertText = null

    extend this, @options

  computeRelevancy: ->
    # We assume that, once the relevancy has been set, it won't change.  Completers must set either @relevancy
    # or @relevancyFunction.
    @relevancy ?= @relevancyFunction this

  generateHtml: ->
    return @html if @html
    relevancyHtml = if @showRelevancy then "<span class='relevancy'>#{@computeRelevancy()}</span>" else ""
    # NOTE(philc): We're using these vimium-specific class names so we don't collide with the page's CSS.
    @html =
      """
      <div class="vimiumReset vomnibarTopHalf">
         <span class="vimiumReset vomnibarSource">#{@type}</span>
         <span class="vimiumReset vomnibarTitle">#{@highlightQueryTerms Utils.escapeHtml @title}</span>
       </div>
       <div class="vimiumReset vomnibarBottomHalf">
        <span class="vimiumReset vomnibarUrl">#{@highlightQueryTerms Utils.escapeHtml @shortenUrl()}</span>
        #{relevancyHtml}
      </div>
      """

  # Use neat trick to snatch a domain (http://stackoverflow.com/a/8498668).
  getUrlRoot: (url) ->
    a = document.createElement 'a'
    a.href = url
    a.protocol + "//" + a.hostname

  getHostname: (url) ->
    a = document.createElement 'a'
    a.href = url
    a.hostname

  stripTrailingSlash: (url) ->
    url = url.substring(url, url.length - 1) if url[url.length - 1] == "/"
    url

  # Push the ranges within `string` which match `term` onto `ranges`.
  pushMatchingRanges: (string,term,ranges) ->
    textPosition = 0
    # Split `string` into a (flat) list of pairs:
    #   - for i=0,2,4,6,...
    #     - splits[i] is unmatched text
    #     - splits[i+1] is the following matched text (matching `term`)
    #       (except for the final element, for which there is no following matched text).
    # Example:
    #   - string = "Abacab"
    #   - term = "a"
    #   - splits = [ "", "A",    "b", "a",    "c", "a",    b" ]
    #                UM   M       UM   M       UM   M      UM      (M=Matched, UM=Unmatched)
    splits = string.split(RegexpCache.get(term, "(", ")"))
    for index in [0..splits.length-2] by 2
      unmatchedText = splits[index]
      matchedText = splits[index+1]
      # Add the indices spanning `matchedText` to `ranges`.
      textPosition += unmatchedText.length
      ranges.push([textPosition, textPosition + matchedText.length])
      textPosition += matchedText.length

  # Wraps each occurence of the query terms in the given string in a <span>.
  highlightQueryTerms: (string) ->
    return string unless @highlightTerms
    ranges = []
    escapedTerms = @queryTerms.map (term) -> Utils.escapeHtml(term)
    for term in escapedTerms
      @pushMatchingRanges string, term, ranges

    return string if ranges.length == 0

    ranges = @mergeRanges(ranges.sort (a, b) -> a[0] - b[0])
    # Replace portions of the string from right to left.
    ranges = ranges.sort (a, b) -> b[0] - a[0]
    for [start, end] in ranges
      string =
        string.substring(0, start) +
        "<span class='vomnibarMatch'>#{string.substring(start, end)}</span>" +
        string.substring(end)
    string

  # Merges the given list of ranges such that any overlapping regions are combined. E.g.
  #   mergeRanges([0, 4], [3, 6]) => [0, 6].  A range is [startIndex, endIndex].
  mergeRanges: (ranges) ->
    previous = ranges.shift()
    mergedRanges = [previous]
    ranges.forEach (range) ->
      if previous[1] >= range[0]
        previous[1] = Math.max(range[1], previous[1])
      else
        mergedRanges.push(range)
        previous = range
    mergedRanges

  # Simplify a suggestion's URL (by removing those parts which aren't useful for display or comparison).
  shortenUrl: () ->
    return @shortUrl if @shortUrl?
    url = @url
    for [ filter, replacements ] in @stripPatterns
      if new RegExp(filter).test url
        for replace in replacements
          url = url.replace replace, ""
    @shortUrl = url

  # Patterns to strip from URLs; of the form [ [ filter, replacements ], [ filter, replacements ], ... ]
  #   - filter is a regexp string; a URL must match this regexp first.
  #   - replacements (itself a list) is a list of regexp objects, each of which is removed from URLs matching
  #     the filter.
  #
  # Note. This includes site-specific patterns for very-popular sites with URLs which don't work well in the
  # vomnibar.
  #
  stripPatterns: [
    # Google search specific replacements; this replaces query parameters which are known to not be helpful.
    # There's some additional information here: http://www.teknoids.net/content/google-search-parameters-2012
    [ "^https?://www\.google\.(com|ca|com\.au|co\.uk|ie)/.*[&?]q="
      "ei gws_rd url ved usg sa usg sig2 bih biw cd aqs ie sourceid es_sm"
        .split(/\s+/).map (param) -> new RegExp "\&#{param}=[^&]+" ]

    # General replacements; replaces leading and trailing fluff.
    [ '.', [ "^https?://", "\\W+$" ].map (re) -> new RegExp re ]
  ]

class BookmarkCompleter
  folderSeparator: "/"
  currentSearch: null
  # These bookmarks are loaded asynchronously when refresh() is called.
  bookmarks: null

  filter: ({ @queryTerms }, @onComplete) ->
    @currentSearch = { queryTerms: @queryTerms, onComplete: @onComplete }
    @performSearch() if @bookmarks

  onBookmarksLoaded: -> @performSearch() if @currentSearch

  performSearch: ->
    # If the folder separator character the first character in any query term, then we'll use the bookmark's full path as its title.
    # Otherwise, we'll just use the its regular title.
    usePathAndTitle = @currentSearch.queryTerms.reduce ((prev,term) => prev || term.indexOf(@folderSeparator) == 0), false
    results =
      if @currentSearch.queryTerms.length > 0
        @bookmarks.filter (bookmark) =>
          suggestionTitle = if usePathAndTitle then bookmark.pathAndTitle else bookmark.title
          RankingUtils.matches(@currentSearch.queryTerms, bookmark.url, suggestionTitle)
      else
        []
    suggestions = results.map (bookmark) =>
      new Suggestion
        queryTerms: @currentSearch.queryTerms
        type: "bookmark"
        url: bookmark.url
        title: if usePathAndTitle then bookmark.pathAndTitle else bookmark.title
        relevancyFunction: @computeRelevancy
    onComplete = @currentSearch.onComplete
    @currentSearch = null
    onComplete suggestions

  refresh: ->
    @bookmarks = null
    chrome.bookmarks.getTree (bookmarks) =>
      @bookmarks = @traverseBookmarks(bookmarks).filter((bookmark) -> bookmark.url?)
      @onBookmarksLoaded()

  # If these names occur as top-level bookmark names, then they are not included in the names of bookmark folders.
  ignoreTopLevel:
    'Other Bookmarks': true
    'Mobile Bookmarks': true
    'Bookmarks Bar': true

  # Traverses the bookmark hierarchy, and returns a flattened list of all bookmarks.
  traverseBookmarks: (bookmarks) ->
    results = []
    bookmarks.forEach (folder) =>
      @traverseBookmarksRecursive folder, results
    results

  # Recursive helper for `traverseBookmarks`.
  traverseBookmarksRecursive: (bookmark, results, parent={pathAndTitle:""}) ->
    bookmark.pathAndTitle =
      if bookmark.title and not (parent.pathAndTitle == "" and @ignoreTopLevel[bookmark.title])
        parent.pathAndTitle + @folderSeparator + bookmark.title
      else
        parent.pathAndTitle
    results.push bookmark
    bookmark.children.forEach((child) => @traverseBookmarksRecursive child, results, bookmark) if bookmark.children

  computeRelevancy: (suggestion) ->
    RankingUtils.wordRelevancy(suggestion.queryTerms, suggestion.url, suggestion.title)

class HistoryCompleter
  filter: ({ queryTerms }, onComplete) ->
    @currentSearch = { queryTerms: @queryTerms, onComplete: @onComplete }
    results = []
    HistoryCache.use (history) =>
      results =
        if queryTerms.length > 0
          history.filter (entry) -> RankingUtils.matches(queryTerms, entry.url, entry.title)
        else
          []
      onComplete results.map (entry) =>
        new Suggestion
          queryTerms: queryTerms
          type: "history"
          url: entry.url
          title: entry.title
          relevancyFunction: @computeRelevancy
          relevancyData: entry

  computeRelevancy: (suggestion) ->
    historyEntry = suggestion.relevancyData
    recencyScore = RankingUtils.recencyScore(historyEntry.lastVisitTime)
    wordRelevancy = RankingUtils.wordRelevancy(suggestion.queryTerms, suggestion.url, suggestion.title)
    # Average out the word score and the recency. Recency has the ability to pull the score up, but not down.
    (wordRelevancy + Math.max recencyScore, wordRelevancy) / 2

# The domain completer is designed to match a single-word query which looks like it is a domain. This supports
# the user experience where they quickly type a partial domain, hit tab -> enter, and expect to arrive there.
class DomainCompleter
  # A map of domain -> { entry: <historyEntry>, referenceCount: <count> }
  #  - `entry` is the most recently accessed page in the History within this domain.
  #  - `referenceCount` is a count of the number of History entries within this domain.
  #     If `referenceCount` goes to zero, the domain entry can and should be deleted.
  domains: null

  filter: ({ queryTerms, query }, onComplete) ->
    # Do not offer completions if the query is empty, or if the user has finished typing the first word.
    return onComplete [] if queryTerms.length == 0 or /\S\s/.test query
    if @domains
      @performSearch(queryTerms, onComplete)
    else
      @populateDomains => @performSearch(queryTerms, onComplete)

  performSearch: (queryTerms, onComplete) ->
    query = queryTerms[0]
    domains = (domain for domain of @domains when 0 <= domain.indexOf query)
    domains = @sortDomainsByRelevancy queryTerms, domains
    onComplete [
      new Suggestion
        queryTerms: queryTerms
        type: "domain"
        url: domains[0]?[0] ? "" # This is the URL or an empty string, but not null.
        relevancy: 1
      ].filter (s) -> 0 < s.url.length

  # Returns a list of domains of the form: [ [domain, relevancy], ... ]
  sortDomainsByRelevancy: (queryTerms, domainCandidates) ->
    results =
      for domain in domainCandidates
        recencyScore = RankingUtils.recencyScore(@domains[domain].entry.lastVisitTime || 0)
        wordRelevancy = RankingUtils.wordRelevancy queryTerms, domain, null
        score = (wordRelevancy + Math.max(recencyScore, wordRelevancy)) / 2
        [domain, score]
    results.sort (a, b) -> b[1] - a[1]
    results

  populateDomains: (onComplete) ->
    HistoryCache.use (history) =>
      @domains = {}
      history.forEach (entry) => @onPageVisited entry
      chrome.history.onVisited.addListener(@onPageVisited.bind(this))
      chrome.history.onVisitRemoved.addListener(@onVisitRemoved.bind(this))
      onComplete()

  onPageVisited: (newPage) ->
    domain = @parseDomainAndScheme newPage.url
    if domain
      slot = @domains[domain] ||= { entry: newPage, referenceCount: 0 }
      # We want each entry in our domains hash to point to the most recent History entry for that domain.
      slot.entry = newPage if slot.entry.lastVisitTime < newPage.lastVisitTime
      slot.referenceCount += 1

  onVisitRemoved: (toRemove) ->
    if toRemove.allHistory
      @domains = {}
    else
      toRemove.urls.forEach (url) =>
        domain = @parseDomainAndScheme url
        if domain and @domains[domain] and ( @domains[domain].referenceCount -= 1 ) == 0
          delete @domains[domain]

  # Return something like "http://www.example.com" or false.
  parseDomainAndScheme: (url) ->
      Utils.hasFullUrlPrefix(url) and not Utils.hasChromePrefix(url) and url.split("/",3).join "/"

# TabRecency associates a logical timestamp with each tab id.  These are used to provide an initial
# recency-based ordering in the tabs vomnibar (which allows jumping quickly between recently-visited tabs).
class TabRecency
  timestamp: 1
  current: -1
  cache: {}
  lastVisited: null
  lastVisitedTime: null
  timeDelta: 500 # Milliseconds.

  constructor: ->
    chrome.tabs.onActivated.addListener (activeInfo) => @register activeInfo.tabId
    chrome.tabs.onRemoved.addListener (tabId) => @deregister tabId

    chrome.tabs.onReplaced.addListener (addedTabId, removedTabId) =>
      @deregister removedTabId
      @register addedTabId

  register: (tabId) ->
    currentTime = new Date()
    # Register tabId if it has been visited for at least @timeDelta ms.  Tabs which are visited only for a
    # very-short time (e.g. those passed through with `5J`) aren't registered as visited at all.
    if @lastVisitedTime? and @timeDelta <= currentTime - @lastVisitedTime
      @cache[@lastVisited] = ++@timestamp

    @current = @lastVisited = tabId
    @lastVisitedTime = currentTime

  deregister: (tabId) ->
    if tabId == @lastVisited
      # Ensure we don't register this tab, since it's going away.
      @lastVisited = @lastVisitedTime = null
    delete @cache[tabId]

  # Recently-visited tabs get a higher score (except the current tab, which gets a low score).
  recencyScore: (tabId) ->
    @cache[tabId] ||= 1
    if tabId == @current then 0.0 else @cache[tabId] / @timestamp

tabRecency = new TabRecency()

# Searches through all open tabs, matching on title and URL.
class TabCompleter
  filter: ({ queryTerms }, onComplete) ->
    # NOTE(philc): We search all tabs, not just those in the current window. I'm not sure if this is the
    # correct UX.
    chrome.tabs.query {}, (tabs) =>
      results = tabs.filter (tab) -> RankingUtils.matches(queryTerms, tab.url, tab.title)
      suggestions = results.map (tab) =>
        new Suggestion
          queryTerms: queryTerms
          type: "tab"
          url: tab.url
          title: tab.title
          relevancyFunction: @computeRelevancy
          tabId: tab.id
      onComplete suggestions

  computeRelevancy: (suggestion) ->
    if suggestion.queryTerms.length
      RankingUtils.wordRelevancy(suggestion.queryTerms, suggestion.url, suggestion.title)
    else
      tabRecency.recencyScore(suggestion.tabId)

class SearchEngineCompleter
  @debug: false
  searchEngines: null

  constructor: (@defaultSearchOnly = false) ->
  cancel: -> CompletionSearch.cancel()

  # This looks up the custom search engine and, if one is found, notes it and removes its keyword from the
  # query terms.
  triageRequest: (request) ->
    @searchEngines.use (engines) =>
      { queryTerms, query } = request
      keyword = queryTerms[0]
      # Note. For a keyword "w", we match "w search terms" and "w ", but not "w" on its own.
      if keyword and engines[keyword] and (1 < queryTerms.length or /\s$/.test query)
        extend request,
          queryTerms: queryTerms[1..]
          keyword: keyword
          engine: engines[keyword]

  refresh: (port) ->
    # Parse the search-engine configuration.
    @searchEngines = new AsyncDataFetcher (callback) =>
      return callback {} if @defaultSearchOnly
      engines = {}
      for line in Settings.get("searchEngines").split "\n"
        line = line.trim()
        continue if /^[#"]/.test line
        tokens = line.split /\s+/
        continue unless 2 <= tokens.length
        keyword = tokens[0].split(":")[0]
        url = tokens[1]
        description = tokens[2..].join(" ") || "search (#{keyword})"
        continue unless Utils.hasFullUrlPrefix url
        engines[keyword] =
          keyword: keyword
          searchUrl: url
          description: description
          searchUrlPrefix: url.split("%s")[0]

      callback engines

      # Let the front-end vomnibar know the search-engine keywords.  It needs to know them so that, when the
      # query goes from "w" to "w ", the vomnibar can synchronously launch the next filter() request (which
      # avoids an ugly delay/flicker).
      port.postMessage
        handler: "keywords"
        keywords: key for own key of engines

  filter: (request, onComplete) ->
    { queryTerms, query, engine } = request

    { custom, searchUrl, description } =
      if engine
        { keyword, searchUrl, description } = engine
        extend request, { searchUrl, customSearchMode: true }
        custom: true
        searchUrl: searchUrl
        description: description
      else
        custom: false
        searchUrl: Settings.get "searchUrl"
        description: "search"

    return onComplete [] unless custom or 0 < queryTerms.length

    factor = Math.max 0.0, Math.min 1.0, Settings.get "omniSearchWeight"
    haveCompletionEngine = (0.0 < factor or custom) and CompletionSearch.haveCompletionEngine searchUrl

    # Relevancy:
    #   - Relevancy does not depend upon the actual suggestion (so, it does not depend upon word
    #     relevancy, say).  We assume that the completion engine has already factored that in.  Also,
    #     completion engines sometimes handle spelling mistakes, in which case we wouldn't find the query
    #     terms in the suggestion anyway.
    #   - Scores are weighted such that they retain the order provided by the completion engine.
    #   - The relavancy is higher if the query term is longer.  The idea is that search suggestions are more
    #     likely to be relevant if, after typing some number of characters, the user hasn't yet found
    #     a useful suggestion from another completer.
    #
    characterCount = query.length - queryTerms.length + 1
    relevancy = (if custom then 0.5 else factor) * 12.0 / Math.max 12.0, characterCount

    # This filter is applied to all of the suggestions from all of the completers, after they have been
    # aggregated by the MultiCompleter.
    filter = (suggestions) ->
      return suggestions unless custom and haveCompletionEngine

      # We only accept suggestions:
      #   - from this completer, or
      #   - from other completers, but then only if their URL matches this search engine and matches this
      #   query (that is only if their URL could have been generated by this search engine).
      suggestions.filter (suggestion) ->
        suggestion.type == description or
          # This is a suggestion for the same search engine.
          (suggestion.url.startsWith(engine.searchUrlPrefix) and
            # And the URL suffix (which must contain the query part) matches the current query.
            RankingUtils.matches queryTerms, suggestion.url[engine.searchUrlPrefix.length..])

    primarySuggestion = new Suggestion
      queryTerms: queryTerms
      type: description
      url: Utils.createSearchUrl queryTerms, searchUrl
      title: queryTerms.join " "
      relevancy: 1
      autoSelect: custom
      forceAutoSelect: custom
      highlightTerms: not haveCompletionEngine
      isCustomSearch: custom

    mkSuggestion = (suggestion) ->
      new Suggestion
        queryTerms: queryTerms
        type: description
        url: Utils.createSearchUrl suggestion, searchUrl
        title: suggestion
        relevancy: relevancy *= 0.9
        insertText: suggestion
        highlightTerms: false
        isCustomSearch: custom

    cachedSuggestions =
      if haveCompletionEngine then CompletionSearch.complete searchUrl, queryTerms else null

    suggestions = []
    suggestions.push primarySuggestion if custom
    suggestions.push cachedSuggestions.map(mkSuggestion)... if custom and cachedSuggestions?

    if queryTerms.length == 0 or cachedSuggestions? or not haveCompletionEngine
      # There is no prospect of adding further completions.
      suggestions.push cachedSuggestions.map(mkSuggestion)... if cachedSuggestions?
      onComplete suggestions, { filter, continuation: null }
    else
      # Post the initial suggestions, but then deliver any further completions asynchronously, as a
      # continuation.
      onComplete suggestions,
        filter: filter
        continuation: (suggestions, onComplete) =>
          # Fetch completion suggestions from suggestion engines.

          # We can skip this if any new suggestions we propose cannot score highly enough to make the list
          # anyway.
          if 10 <= suggestions.length and relevancy < suggestions[suggestions.length-1].relevancy
            console.log "skip (cannot make the grade):", suggestions.length, query if SearchEngineCompleter.debug
            return onComplete []

          CompletionSearch.complete searchUrl, queryTerms, (suggestions = []) =>
            console.log "fetched suggestions:", suggestions.length, query if SearchEngineCompleter.debug
            onComplete suggestions.map mkSuggestion

# A completer which provides completions based on the user's query history using this default search URL.
#
# QueryHistory entries are stored in chrome.storage.local under the key "vomnibarQueryHistory" in the form:
#   [ { text: ..., timestamp: ...}, ... ]
#
# Insertions only happen in vomnibar.coffee(), and new entries are only ever appended.  Therefore, the list is
# always ordered from least recent (at the start) to most recent (at the end).
#
class QueryHistoryCompleter
  maxHistory: 1000

  constructor: ->
    @createQueryHistoryFromHistory()
    chrome.storage.onChanged.addListener (changes, area) =>
      if area == "local" and changes.vomnibarQueryHistory?.newValue
        seenHistory = {}
        # We need to eliminate duplicates.  New items are add at the end, so we reverse the list before
        # checking (so that we pick up the item with the newest timestamp first).  We then reverse the list
        # again when saving it.
        queryHistory =
          for item in changes.vomnibarQueryHistory.newValue.reverse()
            continue if item.text of seenHistory
            seenHistory[item.text] = item

        chrome.storage.local.set vomnibarQueryHistory: queryHistory[0...@maxHistory].reverse()

  filter: ({ queryTerms, query }, onComplete) ->
    chrome.storage.local.get "vomnibarQueryHistory", (items) =>
      if chrome.runtime.lastError
        onComplete []
      else
        queryHistory = (items.vomnibarQueryHistory ? []).filter (item) ->
          RankingUtils.matches queryTerms, item.text
        suggestions = []

        suggestions.push new Suggestion
          queryTerms: queryTerms
          type: "search engine"
          url: Utils.createSearchUrl queryTerms.join " "
          title: query
          relevancy: 1
          insertText: null
          queryText: queryTerms.join " "
          autoSelect: true
          highlightTerms: false

        for { text, timestamp } in queryHistory
          url = Utils.convertToUrl text
          if queryTerms.length == 0 or RankingUtils.matches queryTerms, url, text
            suggestions.push new Suggestion
              queryTerms: queryTerms
              type: "query history"
              url: Utils.convertToUrl text
              title: text
              relevancyFunction: @computeRelevancy
              timestamp: timestamp
              insertText: text

        onComplete suggestions

  computeRelevancy: ({ queryTerms, url, title, timestamp }) ->
    wordRelevancy = if queryTerms.length == 0 then 0.0 else RankingUtils.wordRelevancy queryTerms, url, title
    oneDayAgo = 1000 * 60 * 60 * 24
    age = new Date() - Math.max timestamp, oneDayAgo
    recencyScore = Math.pow 0.999, (age / (1000 * 60 * 60 * 10))
    if queryTerms.length == 0
      recencyScore
    else
      # We give a strong bias towards the recency score, because the function of the query completer is
      # intended to be for finding recent searches.
      if wordRelevancy == 0 then 0 else (recencyScore * 0.7) + wordRelevancy * 0.3

  # Import query history ("vomnibarQueryHistory" in crome.storage.local) from history.
  # We take a history entry of the form "https://www.google.ie/search?q=pakistan+cricket+team&gws_rd=cr,ssl".
  # And produce a query history entry with the text "pakistan cricket team".
  #
  # NOTE(smblott) This is migration code, added 2015-5-15.  It can safely be removed after some suitable
  # period of time (and number of releases) has elapsed.
  #
  createQueryHistoryFromHistory: ->
    chrome.storage.local.get "vomnibarQueryHistory", (items) =>
      unless chrome.runtime.lastError or items.vomnibarQueryHistory
        HistoryCache.use (history) =>
          searchUrl = Settings.get "searchUrl"
          queryHistory =
            for entry in history
              [ url, timestamp ] = [ entry.url, entry.lastVisitTime ]
              continue unless url.startsWith searchUrl
              # We use try/catch because decodeURIComponent can raise an exception.
              try
                text = url[searchUrl.length..].split(/[/&?#]/)[0].split("+").map(decodeURIComponent).join " "
              catch
                continue
              continue unless text? and 0 < text.length
              { text, timestamp }

          # Sort into decreasing order (by timestamp) and remove duplicates.
          queryHistory.sort (a,b) -> b.timestamp - a.timestamp
          [ seenText, seenCount ] = [ {}, 0 ]
          queryHistory =
            for entry in queryHistory
              continue if entry.text of seenText
              break if @maxHistory <= seenCount++
              seenText[text] = entry

          # Save to chrome.storage.local in increasing order (by timestamp).
          chrome.storage.local.set vomnibarQueryHistory: queryHistory.reverse()

# A completer which calls filter() on many completers, aggregates the results, ranks them, and returns the top
# 10. All queries from the vomnibar come through a multi completer.
class MultiCompleter
  maxResults: 10
  filterInProgress: false
  mostRecentQuery: null

  constructor: (@completers) ->
  refresh: (port) -> completer.refresh? port for completer in @completers
  cancel: (port) -> completer.cancel? port for completer in @completers

  filter: (request, onComplete) ->
    # Allow only one query to run at a time.
    return @mostRecentQuery = arguments if @filterInProgress

    # Provide each completer with an opportunity to see (and possibly alter) the request before it is
    # launched.
    completer.triageRequest? request for completer in @completers

    RegexpCache.clear()
    { queryTerms } = request

    [ @mostRecentQuery, @filterInProgress ] = [ null, true ]
    [ suggestions, continuations, filters ] = [ [], [], [] ]

    # Run each of the completers (asynchronously).
    jobs = new JobRunner @completers.map (completer) ->
      (callback) ->
        completer.filter request, (newSuggestions = [], { continuation, filter } = {}) ->
          suggestions.push newSuggestions...
          continuations.push continuation if continuation?
          filters.push filter if filter?
          callback()

    # Once all completers have finished, process the results and post them, and run any continuations or a
    # pending query.
    jobs.onReady =>
      suggestions = filter suggestions for filter in filters
      shouldRunContinuations = 0 < continuations.length and not @mostRecentQuery?

      # Post results, unless there are none and we will be running a continuation.  This avoids
      # collapsing the vomnibar briefly before expanding it again, which looks ugly.
      unless suggestions.length == 0 and shouldRunContinuations
        suggestions = @prepareSuggestions queryTerms, suggestions
        onComplete
          results: suggestions
          mayCacheResults: continuations.length == 0

      # Run any continuations (asynchronously); for example, the search-engine completer
      # (SearchEngineCompleter) uses a continuation to fetch suggestions from completion engines
      # asynchronously.
      if shouldRunContinuations
        jobs = new JobRunner continuations.map (continuation) ->
          (callback) ->
            continuation suggestions, (newSuggestions) ->
              suggestions.push newSuggestions...
              callback()

        jobs.onReady =>
          suggestions = filter suggestions for filter in filters
          suggestions = @prepareSuggestions queryTerms, suggestions
          # We post these results even if a new query has started.  The vomnibar will not display them
          # (because they're arriving too late), but it will cache them.
          onComplete
            results: suggestions
            mayCacheResults: true

      # Admit subsequent queries and launch any pending query.
      @filterInProgress = false
      if @mostRecentQuery
        @filter @mostRecentQuery...

  prepareSuggestions: (queryTerms, suggestions) ->
    # Compute suggestion relevancies and sort.
    suggestion.computeRelevancy queryTerms for suggestion in suggestions
    suggestions.sort (a, b) -> b.relevancy - a.relevancy

    # Simplify URLs and remove duplicates (duplicate simplified URLs, that is).
    count = 0
    seenUrls = {}
    suggestions =
      for suggestion in suggestions
        url = suggestion.shortenUrl()
        continue if seenUrls[url]
        break if count++ == @maxResults
        seenUrls[url] = suggestion

    # Generate HTML for the remaining suggestions and return them.
    suggestion.generateHtml() for suggestion in suggestions
    suggestions

# A completer which can toggle between two or more sub-completers (which must themselves be MultiCompleters).
# The active completer is determined based on request.tabToggleCount, which is provided by the vomnibar.
class ToggleCompleter
  constructor: (@completers) ->

  refresh: (port) -> completer.refresh? port for completer in @completers
  cancel: (port) -> completer.cancel? port for completer in @completers

  filter: (request, onComplete) ->
    @completers[request.tabToggleCount % @completers.length].filter request, onComplete

# Utilities which help us compute a relevancy score for a given item.
RankingUtils =
  # Whether the given things (usually URLs or titles) match any one of the query terms.
  # This is used to prune out irrelevant suggestions before we try to rank them, and for calculating word relevancy.
  # Every term must match at least one thing.
  matches: (queryTerms, things...) ->
    for term in queryTerms
      regexp = RegexpCache.get(term)
      matchedTerm = false
      for thing in things
        matchedTerm ||= thing.match regexp
      return false unless matchedTerm
    true

  # Weights used for scoring matches.
  matchWeights:
    matchAnywhere:     1
    matchStartOfWord:  1
    matchWholeWord:    1
    # The following must be the sum of the three weights above; it is used for normalization.
    maximumScore:      3
    #
    # Calibration factor for balancing word relevancy and recency.
    recencyCalibrator: 2.0/3.0
    # The current value of 2.0/3.0 has the effect of:
    #   - favoring the contribution of recency when matches are not on word boundaries ( because 2.0/3.0 > (1)/3     )
    #   - favoring the contribution of word relevance when matches are on whole words  ( because 2.0/3.0 < (1+1+1)/3 )

  # Calculate a score for matching term against string.
  # The score is in the range [0, matchWeights.maximumScore], see above.
  # Returns: [ score, count ], where count is the number of matched characters in string.
  scoreTerm: (term, string) ->
    score = 0
    count = 0
    nonMatching = string.split(RegexpCache.get term)
    if nonMatching.length > 1
      # Have match.
      score = RankingUtils.matchWeights.matchAnywhere
      count = nonMatching.reduce(((p,c) -> p - c.length), string.length)
      if RegexpCache.get(term, "\\b").test string
        # Have match at start of word.
        score += RankingUtils.matchWeights.matchStartOfWord
        if RegexpCache.get(term, "\\b", "\\b").test string
          # Have match of whole word.
          score += RankingUtils.matchWeights.matchWholeWord
    [ score, if count < string.length then count else string.length ]

  # Returns a number between [0, 1] indicating how often the query terms appear in the url and title.
  wordRelevancy: (queryTerms, url, title) ->
    urlScore = titleScore = 0.0
    urlCount = titleCount = 0
    # Calculate initial scores.
    for term in queryTerms
      [ s, c ] = RankingUtils.scoreTerm term, url
      urlScore += s
      urlCount += c
      if title
        [ s, c ] = RankingUtils.scoreTerm term, title
        titleScore += s
        titleCount += c

    maximumPossibleScore = RankingUtils.matchWeights.maximumScore * queryTerms.length

    # Normalize scores.
    urlScore /= maximumPossibleScore
    urlScore *= RankingUtils.normalizeDifference urlCount, url.length

    if title
      titleScore /= maximumPossibleScore
      titleScore *= RankingUtils.normalizeDifference titleCount, title.length
    else
      titleScore = urlScore

    # Prefer matches in the title over matches in the URL.
    # In other words, don't let a poor urlScore pull down the titleScore.
    # For example, urlScore can be unreasonably poor if the URL is very long.
    urlScore = titleScore if urlScore < titleScore

    # Return the average.
    (urlScore + titleScore) / 2

    # Untested alternative to the above:
    #   - Don't let a poor urlScore pull down a good titleScore, and don't let a poor titleScore pull down a
    #     good urlScore.
    #
    # return Math.max(urlScore, titleScore)

  # Returns a score between [0, 1] which indicates how recent the given timestamp is. Items which are over
  # a month old are counted as 0. This range is quadratic, so an item from one day ago has a much stronger
  # score than an item from two days ago.
  recencyScore: (lastAccessedTime) ->
    @oneMonthAgo ||= 1000 * 60 * 60 * 24 * 30
    recency = Date.now() - lastAccessedTime
    recencyDifference = Math.max(0, @oneMonthAgo - recency) / @oneMonthAgo

    # recencyScore is between [0, 1]. It is 1 when recenyDifference is 0. This quadratic equation will
    # incresingly discount older history entries.
    recencyScore = recencyDifference * recencyDifference * recencyDifference

    # Calibrate recencyScore vis-a-vis word-relevancy scores.
    recencyScore *= RankingUtils.matchWeights.recencyCalibrator

  # Takes the difference of two numbers and returns a number between [0, 1] (the percentage difference).
  normalizeDifference: (a, b) ->
    max = Math.max(a, b)
    (max - Math.abs(a - b)) / max

# We cache regexps because we use them frequently when comparing a query to history entries and bookmarks,
# and we don't want to create fresh objects for every comparison.
RegexpCache =
  init: ->
    @initialized = true
    @clear()
    # Taken from http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
    @escapeRegExp ||= /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g

  clear: -> @cache = {}

  # Get rexexp for `string` from cache, creating it if necessary.
  # Regexp meta-characters in `string` are escaped.
  # Regexp is wrapped in `prefix`/`suffix`, which may contain meta-characters (these are not escaped).
  # With their default values, `prefix` and `suffix` have no effect.
  # Example:
  #   - string="go", prefix="\b", suffix=""
  #   - this returns regexp matching "google", but not "agog" (the "go" must occur at the start of a word)
  # TODO: `prefix` and `suffix` might be useful in richer word-relevancy scoring.
  get: (string, prefix="", suffix="") ->
    @init() unless @initialized
    regexpString = string.replace(@escapeRegExp, "\\$&")
    # Avoid cost of constructing new strings if prefix/suffix are empty (which is expected to be a common case).
    regexpString = prefix + regexpString if prefix
    regexpString = regexpString + suffix if suffix
    # Smartcase: Regexp is case insensitive, unless `string` contains a capital letter (testing `string`, not `regexpString`).
    @cache[regexpString] ||= new RegExp regexpString, (if Utils.hasUpperCase(string) then "" else "i")

# Provides cached access to Chrome's history. As the user browses to new pages, we add those pages to this
# history cache.
HistoryCache =
  size: 20000
  history: null # An array of History items returned from Chrome.

  reset: ->
    @history = null
    @callbacks = null

  use: (callback) ->
    if @history? then callback @history else @fetchHistory callback

  fetchHistory: (callback) ->
    return @callbacks.push(callback) if @callbacks
    @callbacks = [callback]
    chrome.history.search { text: "", maxResults: @size, startTime: 0 }, (history) =>
      history.sort @compareHistoryByUrl
      @history = history
      chrome.history.onVisited.addListener(@onPageVisited.bind(this))
      chrome.history.onVisitRemoved.addListener(@onVisitRemoved.bind(this))
      callback(@history) for callback in @callbacks
      @callbacks = null

  compareHistoryByUrl: (a, b) ->
    return 0 if a.url == b.url
    return 1 if a.url > b.url
    -1

  # When a page we've seen before has been visited again, be sure to replace our History item so it has the
  # correct "lastVisitTime". That's crucial for ranking Vomnibar suggestions.
  onPageVisited: (newPage) ->
    i = HistoryCache.binarySearch(newPage, @history, @compareHistoryByUrl)
    pageWasFound = (@history[i].url == newPage.url)
    if pageWasFound
      @history[i] = newPage
    else
      @history.splice(i, 0, newPage)

  # When a page is removed from the chrome history, remove it from the vimium history too.
  onVisitRemoved: (toRemove) ->
    if toRemove.allHistory
      @history = []
    else
      toRemove.urls.forEach (url) =>
        i = HistoryCache.binarySearch({url:url}, @history, @compareHistoryByUrl)
        if i < @history.length and @history[i].url == url
          @history.splice(i, 1)

# Returns the matching index or the closest matching index if the element is not found. That means you
# must check the element at the returned index to know whether the element was actually found.
# This method is used for quickly searching through our history cache.
HistoryCache.binarySearch = (targetElement, array, compareFunction) ->
  high = array.length - 1
  low = 0

  while (low <= high)
    middle = Math.floor((low + high) / 2)
    element = array[middle]
    compareResult = compareFunction(element, targetElement)
    if (compareResult > 0)
      high = middle - 1
    else if (compareResult < 0)
      low = middle + 1
    else
      return middle
  # We didn't find the element. Return the position where it should be in this array.
  return if compareFunction(element, targetElement) < 0 then middle + 1 else middle

root = exports ? window
root.Suggestion = Suggestion
root.BookmarkCompleter = BookmarkCompleter
root.MultiCompleter = MultiCompleter
root.ToggleCompleter = ToggleCompleter
root.HistoryCompleter = HistoryCompleter
root.DomainCompleter = DomainCompleter
root.TabCompleter = TabCompleter
root.SearchEngineCompleter = SearchEngineCompleter
root.HistoryCache = HistoryCache
root.RankingUtils = RankingUtils
root.RegexpCache = RegexpCache
root.TabRecency = TabRecency
root.QueryHistoryCompleter = QueryHistoryCompleter

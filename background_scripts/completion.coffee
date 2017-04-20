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
  showRelevancy: false # Set this to true to render relevancy when debugging the ranking scores.

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
    # If @autoSelect is truthy, then this suggestion is automatically pre-selected in the vomnibar.  This only
    # affects the suggestion in slot 0 in the vomnibar.
    @autoSelect = false
    # If @highlightTerms is true, then we highlight matched terms in the title and URL.  Otherwise we don't.
    @highlightTerms = true
    # @insertText is text to insert into the vomnibar input when the suggestion is selected.
    @insertText = null
    # @deDuplicate controls whether this suggestion is a candidate for deduplication.
    @deDuplicate = true

    # Other options set by individual completers include:
    # - tabId (TabCompleter)
    # - isSearchSuggestion, customSearchMode (SearchEngineCompleter)

    extend this, @options

  computeRelevancy: ->
    # We assume that, once the relevancy has been set, it won't change.  Completers must set either @relevancy
    # or @relevancyFunction.
    @relevancy ?= @relevancyFunction this

  generateHtml: (request) ->
    return @html if @html
    relevancyHtml = if @showRelevancy then "<span class='relevancy'>#{@computeRelevancy()}</span>" else ""
    insertTextClass = if @insertText then "vomnibarInsertText" else "vomnibarNoInsertText"
    insertTextIndicator = "&#8618;" # A right hooked arrow.
    @title = @insertText if @insertText and request.isCustomSearch
    # NOTE(philc): We're using these vimium-specific class names so we don't collide with the page's CSS.
    @html =
      if request.isCustomSearch
        """
        <div class="vimiumReset vomnibarTopHalf">
           <span class="vimiumReset vomnibarSource #{insertTextClass}">#{insertTextIndicator}</span><span class="vimiumReset vomnibarSource">#{@type}</span>
           <span class="vimiumReset vomnibarTitle">#{@highlightQueryTerms Utils.escapeHtml @title}</span>
           #{relevancyHtml}
         </div>
        """
      else
        """
        <div class="vimiumReset vomnibarTopHalf">
           <span class="vimiumReset vomnibarSource #{insertTextClass}">#{insertTextIndicator}</span><span class="vimiumReset vomnibarSource">#{@type}</span>
           <span class="vimiumReset vomnibarTitle">#{@highlightQueryTerms Utils.escapeHtml @title}</span>
         </div>
         <div class="vimiumReset vomnibarBottomHalf">
          <span class="vimiumReset vomnibarSource vomnibarNoInsertText">#{insertTextIndicator}</span><span class="vimiumReset vomnibarUrl">#{@highlightUrlTerms Utils.escapeHtml @shortenUrl()}</span>
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

  highlightUrlTerms: (string) ->
    if @highlightTermsExcludeUrl then string else @highlightQueryTerms string

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
    # We get easier-to-read shortened URLs if we URI-decode them.
    url = (Utils.decodeURIByParts(@url) || @url).toLowerCase()
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
    [ "^https?://www\\.google\\.(com|ca|com\\.au|co\\.uk|ie)/.*[&?]q="
      "ei gws_rd url ved usg sa usg sig2 bih biw cd aqs ie sourceid es_sm"
        .split(/\s+/).map (param) -> new RegExp "\&#{param}=[^&]+" ]

    # On Google maps, we get a new history entry for every pan and zoom event.
    [ "^https?://www\\.google\\.(com|ca|com\\.au|co\\.uk|ie)/maps/place/.*/@"
      [ new RegExp "/@.*" ] ]

    # General replacements; replaces leading and trailing fluff.
    [ '.', [ "^https?://", "\\W+$" ].map (re) -> new RegExp re ]
  ]

  # Boost a relevancy score by a factor (in the range (0,1.0)), while keeping the score in the range [0,1].
  # This makes greater adjustments to scores near the middle of the range (so, very poor relevancy scores
  # remain very poor).
  @boostRelevancyScore: (factor, score) ->
    score + if score < 0.5 then score * factor else (1.0 - score) * factor

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
          bookmark.hasJavascriptPrefix ?= Utils.hasJavascriptPrefix bookmark.url
          bookmark.shortUrl ?= "javascript:..." if bookmark.hasJavascriptPrefix
          suggestionUrl = bookmark.shortUrl ? bookmark.url
          RankingUtils.matches(@currentSearch.queryTerms, suggestionUrl, suggestionTitle)
      else
        []
    suggestions = results.map (bookmark) =>
      new Suggestion
        queryTerms: @currentSearch.queryTerms
        type: "bookmark"
        url: bookmark.url
        title: if usePathAndTitle then bookmark.pathAndTitle else bookmark.title
        relevancyFunction: @computeRelevancy
        shortUrl: bookmark.shortUrl
        deDuplicate: not bookmark.shortUrl?
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
    RankingUtils.wordRelevancy(suggestion.queryTerms, suggestion.shortUrl ? suggestion.url, suggestion.title)

class HistoryCompleter
  filter: ({ queryTerms, seenTabToOpenCompletionList }, onComplete) ->
    if queryTerms.length == 0 and not seenTabToOpenCompletionList
      onComplete []
      # Prime the history cache so that it will (hopefully) be available on the user's next keystroke.
      Utils.nextTick -> HistoryCache.use ->
    else
      HistoryCache.use (history) =>
        results =
          if 0 < queryTerms.length
            history.filter (entry) -> RankingUtils.matches queryTerms, entry.url, entry.title
          else
            # The user has typed <Tab> to open the entire history (sorted by recency).
            history
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
    # If there are no query terms, then relevancy is based on recency alone.
    return recencyScore if suggestion.queryTerms.length == 0
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
    domains = (domain for own domain of @domains when 0 <= domain.indexOf query)
    domains = @sortDomainsByRelevancy queryTerms, domains
    onComplete [
      new Suggestion
        queryTerms: queryTerms
        type: "domain"
        url: domains[0]?[0] ? "" # This is the URL or an empty string, but not null.
        relevancy: 2.0
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
          deDuplicate: false
      onComplete suggestions

  computeRelevancy: (suggestion) ->
    if suggestion.queryTerms.length
      RankingUtils.wordRelevancy(suggestion.queryTerms, suggestion.url, suggestion.title)
    else
      BgUtils.tabRecency.recencyScore(suggestion.tabId)

class SearchEngineCompleter
  @debug: false
  previousSuggestions: null

  cancel: ->
    CompletionSearch.cancel()

  # This looks up the custom search engine and, if one is found, notes it and removes its keyword from the
  # query terms.
  preprocessRequest: (request) ->
    SearchEngines.use (engines) =>
      { queryTerms, query } = request
      extend request, searchEngines: engines, keywords: key for own key of engines
      keyword = queryTerms[0]
      # Note. For a keyword "w", we match "w search terms" and "w ", but not "w" on its own.
      if keyword and engines[keyword] and (1 < queryTerms.length or /\S\s/.test query)
        extend request,
          queryTerms: queryTerms[1..]
          keyword: keyword
          engine: engines[keyword]
          isCustomSearch: true

  refresh: (port) ->
    @previousSuggestions = {}
    SearchEngines.refreshAndUse Settings.get("searchEngines"), (engines) ->
      # Let the front-end vomnibar know the search-engine keywords.  It needs to know them so that, when the
      # query goes from "w" to "w ", the vomnibar can synchronously launch the next filter() request (which
      # avoids an ugly delay/flicker).
      port.postMessage
        handler: "keywords"
        keywords: key for own key of engines

  filter: (request, onComplete) ->
    { queryTerms, query, engine } = request
    return onComplete [] unless engine

    { keyword, searchUrl, description } = engine
    extend request, searchUrl, customSearchMode: true

    @previousSuggestions[searchUrl] ?= []
    haveCompletionEngine = CompletionSearch.haveCompletionEngine searchUrl

    # This filter is applied to all of the suggestions from all of the completers, after they have been
    # aggregated by the MultiCompleter.
    filter = (suggestions) ->
      # We only keep suggestions which either *were* generated by this search engine, or *could have
      # been* generated by this search engine (and match the current query).
      for suggestion in suggestions
        if suggestion.isSearchSuggestion or suggestion.isCustomSearch
          suggestion
        else
          terms = Utils.extractQuery searchUrl, suggestion.url
          continue unless terms and RankingUtils.matches queryTerms, terms
          suggestion.url = Utils.createSearchUrl terms, searchUrl
          suggestion

    # If a previous suggestion still matches the query, then we keep it (even if the completion engine may not
    # return it for the current query).  This allows the user to pick suggestions that they've previously seen
    # by typing fragments of their text, without regard to whether the completion engine can continue to
    # complete the actual text of the query.
    previousSuggestions =
      if queryTerms.length == 0
        []
      else
        for own _, suggestion of @previousSuggestions[searchUrl]
          continue unless RankingUtils.matches queryTerms, suggestion.title
          # Reset various fields, they may not be correct wrt. the current query.
          extend suggestion, relevancy: null, html: null, queryTerms: queryTerms
          suggestion.relevancy = null
          suggestion

    primarySuggestion = new Suggestion
      queryTerms: queryTerms
      type: description
      url: Utils.createSearchUrl queryTerms, searchUrl
      title: queryTerms.join " "
      searchUrl: searchUrl
      relevancy: 2.0
      autoSelect: true
      highlightTerms: false
      isSearchSuggestion: true
      isPrimarySuggestion: true

    return onComplete [ primarySuggestion ], { filter } if queryTerms.length == 0

    mkSuggestion = do =>
      count = 0
      (suggestion) =>
        url = Utils.createSearchUrl suggestion, searchUrl
        @previousSuggestions[searchUrl][url] = new Suggestion
          queryTerms: queryTerms
          type: description
          url: url
          title: suggestion
          searchUrl: searchUrl
          insertText: suggestion
          highlightTerms: false
          highlightTermsExcludeUrl: true
          isCustomSearch: true
          relevancy: if ++count == 1 then 1.0 else null
          relevancyFunction: @computeRelevancy

    cachedSuggestions =
      if haveCompletionEngine then CompletionSearch.complete searchUrl, queryTerms else null

    suggestions = previousSuggestions
    suggestions.push primarySuggestion

    if queryTerms.length == 0 or cachedSuggestions? or not haveCompletionEngine
      # There is no prospect of adding further completions, so we're done.
      suggestions.push cachedSuggestions.map(mkSuggestion)... if cachedSuggestions?
      onComplete suggestions, { filter, continuation: null }
    else
      # Post the initial suggestions, but then deliver any further completions asynchronously, as a
      # continuation.
      onComplete suggestions,
        filter: filter
        continuation: (onComplete) =>
          CompletionSearch.complete searchUrl, queryTerms, (suggestions = []) =>
            console.log "fetched suggestions:", suggestions.length, query if SearchEngineCompleter.debug
            onComplete suggestions.map mkSuggestion

  computeRelevancy: ({ relevancyData, queryTerms, title }) ->
    # Tweaks:
    # - Calibration: we boost relevancy scores to try to achieve an appropriate balance between relevancy
    #   scores here, and those provided by other completers.
    # - Relevancy depends only on the title (which is the search terms), and not on the URL.
    Suggestion.boostRelevancyScore 0.5,
      0.7 * RankingUtils.wordRelevancy queryTerms, title, title

  postProcessSuggestions: (request, suggestions) ->
    return unless request.searchEngines
    engines = (engine for own _, engine of request.searchEngines)
    engines.sort (a,b) -> b.searchUrl.length - a.searchUrl.length
    engines.push keyword: null, description: "search history", searchUrl: Settings.get "searchUrl"
    for suggestion in suggestions
      unless suggestion.isSearchSuggestion or suggestion.insertText
        for engine in engines
          if suggestion.insertText = Utils.extractQuery engine.searchUrl, suggestion.url
            # suggestion.customSearchMode informs the vomnibar that, if the users edits the text from this
            # suggestion, then custom search-engine mode should be activated.
            suggestion.customSearchMode = engine.keyword
            suggestion.title ||= suggestion.insertText
            break

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
    completer.preprocessRequest? request for completer in @completers

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
        suggestions = @prepareSuggestions request, queryTerms, suggestions
        onComplete results: suggestions

      # Run any continuations (asynchronously); for example, the search-engine completer
      # (SearchEngineCompleter) uses a continuation to fetch suggestions from completion engines
      # asynchronously.
      if shouldRunContinuations
        jobs = new JobRunner continuations.map (continuation) ->
          (callback) ->
            continuation (newSuggestions) ->
              suggestions.push newSuggestions...
              callback()

        jobs.onReady =>
          suggestions = filter suggestions for filter in filters
          suggestions = @prepareSuggestions request, queryTerms, suggestions
          onComplete results: suggestions

      # Admit subsequent queries and launch any pending query.
      @filterInProgress = false
      if @mostRecentQuery
        @filter @mostRecentQuery...

  prepareSuggestions: (request, queryTerms, suggestions) ->
    # Compute suggestion relevancies and sort.
    suggestion.computeRelevancy queryTerms for suggestion in suggestions
    suggestions.sort (a, b) -> b.relevancy - a.relevancy

    # Simplify URLs and remove duplicates (duplicate simplified URLs, that is).
    count = 0
    seenUrls = {}
    suggestions =
      for suggestion in suggestions
        url = suggestion.shortenUrl()
        continue if suggestion.deDuplicate and seenUrls[url]
        break if count++ == @maxResults
        seenUrls[url] = suggestion

    # Give each completer the opportunity to tweak the suggestions.
    completer.postProcessSuggestions? request, suggestions for completer in @completers

    # Generate HTML for the remaining suggestions and return them.
    suggestion.generateHtml request for suggestion in suggestions
    suggestions

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
    regexpString = Utils.escapeRegexSpecialCharacters string
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
      # On Firefox, some history entries do not have titles.
      history.map (entry) -> entry.title ?= ""
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
    # On Firefox, some history entries do not have titles.
    newPage.title ?= ""
    i = HistoryCache.binarySearch(newPage, @history, @compareHistoryByUrl)
    pageWasFound = (@history[i]?.url == newPage.url)
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
root.HistoryCompleter = HistoryCompleter
root.DomainCompleter = DomainCompleter
root.TabCompleter = TabCompleter
root.SearchEngineCompleter = SearchEngineCompleter
root.HistoryCache = HistoryCache
root.RankingUtils = RankingUtils
root.RegexpCache = RegexpCache

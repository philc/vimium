
# This is a wrapper class for completion engines.  It handles the case where a custom search engine includes a
# prefix query term (or terms).  For example:
#
#   https://www.google.com/search?q=javascript+%s
#
# In this case, we get better suggestions if we include the term "javascript" in queries sent to the
# completion engine.  This wrapper handles adding such prefixes to completion-engine queries and removing them
# from the resulting suggestions.
class EnginePrefixWrapper
  constructor: (@searchUrl, @engine) ->

  getUrl: (queryTerms) ->
    # This tests whether @searchUrl contains something of the form "...=abc+def+%s...", from which we extract
    # a prefix of the form "abc def ".
    if /\=.+\+%s/.test @searchUrl
      terms = @searchUrl.replace /\+%s.*/, ""
      terms = terms.replace /.*=/, ""
      terms = terms.replace /\+/g, " "

      queryTerms = [ terms.split(" ")..., queryTerms... ]
      prefix = "#{terms} "

      @postprocessSuggestions =
        (suggestions) ->
          for suggestion in suggestions
            continue unless suggestion.startsWith prefix
            suggestion[prefix.length..]

    @engine.getUrl queryTerms

  parse: (xhr) ->
    @postprocessSuggestions @engine.parse xhr

  postprocessSuggestions: (suggestions) -> suggestions

CompletionSearch =
  debug: false
  inTransit: {}
  completionCache: new SimpleCache 2 * 60 * 60 * 1000, 5000 # Two hours, 5000 entries.
  engineCache:new SimpleCache 1000 * 60 * 60 * 1000 # 1000 hours.

  # The amount of time to wait for new requests before launching the current request (for example, if the user
  # is still typing).
  delay: 100

  get: (searchUrl, url, callback) ->
    xhr = new XMLHttpRequest()
    xhr.open "GET", url, true
    xhr.timeout = 2500
    xhr.ontimeout = xhr.onerror = -> callback null
    xhr.send()

    xhr.onreadystatechange = ->
      if xhr.readyState == 4
        callback if xhr.status == 200 then xhr else null

  # Look up the completion engine for this searchUrl.  Because of DummyCompletionEngine, we know there will
  # always be a match.
  lookupEngine: (searchUrl) ->
    if @engineCache.has searchUrl
      @engineCache.get searchUrl
    else
      for engine in CompletionEngines
        engine = new engine()
        return @engineCache.set searchUrl, engine if engine.match searchUrl

  # True if we have a completion engine for this search URL, false otherwise.
  haveCompletionEngine: (searchUrl) ->
    not @lookupEngine(searchUrl).dummy

  # This is the main entry point.
  #  - searchUrl is the search engine's URL, e.g. Settings.get("searchUrl"), or a custom search engine's URL.
  #    This is only used as a key for determining the relevant completion engine.
  #  - queryTerms are the query terms.
  #  - callback will be applied to a list of suggestion strings (which may be an empty list, if anything goes
  #    wrong).
  #
  # If no callback is provided, then we're to provide suggestions only if we can do so synchronously (ie.
  # from a cache).  In this case we just return the results.  Returns null if we cannot service the request
  # synchronously.
  #
  complete: (searchUrl, queryTerms, callback = null) ->
    query = queryTerms.join(" ").toLowerCase()

    returnResultsOnlyFromCache = not callback?
    callback ?= (suggestions) -> suggestions

    # We don't complete queries which are too short: the results are usually useless.
    return callback [] unless 3 < query.length

    # We don't complete regular URLs or Javascript URLs.
    return callback [] if 1 == queryTerms.length and Utils.isUrl query
    return callback [] if Utils.hasJavascriptPrefix query

    completionCacheKey = JSON.stringify [ searchUrl, queryTerms ]
    if @completionCache.has completionCacheKey
      console.log "hit", completionCacheKey if @debug
      return callback @completionCache.get completionCacheKey

    # If the user appears to be typing a continuation of the characters of the most recent query, then we can
    # sometimes re-use the previous suggestions.
    if @mostRecentQuery? and @mostRecentSuggestions? and @mostRecentSearchUrl?
      if searchUrl == @mostRecentSearchUrl
        reusePreviousSuggestions = do =>
          # Verify that the previous query is a prefix of the current query.
          return false unless 0 == query.indexOf @mostRecentQuery.toLowerCase()
          # Verify that every previous suggestion contains the text of the new query.
          # Note: @mostRecentSuggestions may also be empty, in which case we drop though. The effect is that
          # previous queries with no suggestions suppress subsequent no-hope HTTP requests as the user continues
          # to type.
          for suggestion in @mostRecentSuggestions
            return false unless 0 <= suggestion.indexOf query
          # Ok. Re-use the suggestion.
          true

        if reusePreviousSuggestions
          console.log "reuse previous query:", @mostRecentQuery, @mostRecentSuggestions.length if @debug
          return callback @completionCache.set completionCacheKey, @mostRecentSuggestions

    # That's all of the caches we can try.  Bail if the caller is only requesting synchronous results.  We
    # signal that we haven't found a match by returning null.
    return callback null if returnResultsOnlyFromCache

    # We pause in case the user is still typing.
    Utils.setTimeout @delay, handler = @mostRecentHandler = =>
      if handler == @mostRecentHandler
        @mostRecentHandler = null

        # Elide duplicate requests. First fetch the suggestions...
        @inTransit[completionCacheKey] ?= new AsyncDataFetcher (callback) =>
          engine = new EnginePrefixWrapper searchUrl, @lookupEngine searchUrl
          url = engine.getUrl queryTerms

          @get searchUrl, url, (xhr = null) =>
            # Parsing the response may fail if we receive an unexpected or an unexpectedly-formatted response.
            # In all cases, we fall back to the catch clause, below.  Therefore, we "fail safe" in the case of
            # incorrect or out-of-date completion engines.
            try
              suggestions = engine.parse xhr
              # Make all suggestions lower case.  It looks odd when suggestions from one completion engine are
              # upper case, and those from another are lower case.
              suggestions = (suggestion.toLowerCase() for suggestion in suggestions)
              # Filter out the query itself. It's not adding anything.
              suggestions = (suggestion for suggestion in suggestions when suggestion != query)
              console.log "GET", url if @debug
            catch
              suggestions = []
              # We allow failures to be cached too, but remove them after just thirty seconds.
              Utils.setTimeout 30 * 1000, => @completionCache.set completionCacheKey, null
              console.log "fail", url if @debug

            callback suggestions
            delete @inTransit[completionCacheKey]

        # ... then use the suggestions.
        @inTransit[completionCacheKey].use (suggestions) =>
          @mostRecentSearchUrl = searchUrl
          @mostRecentQuery = query
          @mostRecentSuggestions = suggestions
          callback @completionCache.set completionCacheKey, suggestions

  # Cancel any pending (ie. blocked on @delay) queries.  Does not cancel in-flight queries.  This is called
  # whenever the user is typing.
  cancel: ->
    if @mostRecentHandler?
      @mostRecentHandler = null
      console.log "cancel (user is typing)" if @debug

root = exports ? window
root.CompletionSearch = CompletionSearch

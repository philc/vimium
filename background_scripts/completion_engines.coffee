
# A completion engine provides search suggestions for a search engine.  A search engine is identified by a
# "searchUrl", e.g. Settings.get("searchUrl"), or a custom search engine.
#
# Each completion engine defines three functions:
#
#   1. "match" - This takes a searchUrl, and returns a boolean indicating whether this completion engine can
#      perform completion for the given search engine.
#
#   2. "getUrl" - This takes a list of query terms (queryTerms) and generates a completion URL, that is, a URL
#      which will provide completions for this completion engine.
#
#   3. "parse" - This takes a successful XMLHttpRequest object (the request has completed successfully), and
#      returns a list of suggestions (a list of strings).
#
# The main completion entry point is CompletionEngines.complete().  This implements all lookup and caching
# logic.  It is possible to add new completion engines without changing the CompletionEngines infrastructure
# itself.

# A base class for common regexp-based matching engines.
class RegexpEngine
  constructor: (@regexps) ->
  match: (searchUrl) -> Utils.matchesAnyRegexp @regexps, searchUrl

# Several Google completion engines package XML responses in this way.
class GoogleXMLRegexpEngine extends RegexpEngine
  doNotCache: true
  parse: (xhr) ->
    for suggestion in xhr.responseXML.getElementsByTagName "suggestion"
      continue unless suggestion = suggestion.getAttribute "data"
      suggestion

class Google extends GoogleXMLRegexpEngine
  # Example search URL: http://www.google.com/search?q=%s
  constructor: ->
    super [
      # We match the major English-speaking TLDs.
      new RegExp "^https?://[a-z]+\.google\.(com|ie|co\.uk|ca|com\.au)/"
      new RegExp "localhost/cgi-bin/booky" # Only for smblott.
      ]

  getUrl: (queryTerms) ->
    "http://suggestqueries.google.com/complete/search?ss_protocol=legace&client=toolbar&q=#{Utils.createSearchQuery queryTerms}"

class Youtube extends GoogleXMLRegexpEngine
  # Example search URL: http://www.youtube.com/results?search_query=%s
  constructor: ->
    super [ new RegExp "^https?://[a-z]+\.youtube\.com/results" ]

  getUrl: (queryTerms) ->
    "http://suggestqueries.google.com/complete/search?client=youtube&ds=yt&xml=t&q=#{Utils.createSearchQuery queryTerms}"

class Wikipedia extends RegexpEngine
  doNotCache: true
  # Example search URL: http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s
  constructor: ->
    super [ new RegExp "^https?://[a-z]+\.wikipedia\.org/" ]

  getUrl: (queryTerms) ->
    "https://en.wikipedia.org/w/api.php?action=opensearch&format=json&search=#{Utils.createSearchQuery queryTerms}"

  parse: (xhr) ->
    JSON.parse(xhr.responseText)[1]

## class GoogleMaps extends RegexpEngine
##   # Example search URL: https://www.google.com/maps/search/%s
##   constructor: ->
##     super [ new RegExp "^https?://www\.google\.com/maps/search/" ]
##
##   getUrl: (queryTerms) ->
##     console.log "xxxxxxxxxxxxxxxxxxxxx"
##     "https://www.google.com/s?tbm=map&fp=1&gs_ri=maps&source=hp&suggest=p&authuser=0&hl=en&pf=p&tch=1&ech=2&q=#{Utils.createSearchQuery queryTerms}"
##
##   parse: (xhr) ->
##     console.log "yyy", xhr.responseText
##     data = JSON.parse xhr.responseText
##     console.log "zzz"
##     console.log data
##     []

class Bing extends RegexpEngine
  # Example search URL: https://www.bing.com/search?q=%s
  constructor: -> super [ new RegExp "^https?://www\.bing\.com/search" ]
  getUrl: (queryTerms) -> "http://api.bing.com/osjson.aspx?query=#{Utils.createSearchQuery queryTerms}"
  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class Amazon extends RegexpEngine
  # Example search URL: http://www.amazon.com/s/?field-keywords=%s
  constructor: -> super [ new RegExp "^https?://www\.amazon\.(com|co.uk|ca|com.au)/s/" ]
  getUrl: (queryTerms) -> "https://completion.amazon.com/search/complete?method=completion&search-alias=aps&client=amazon-search-ui&mkt=1&q=#{Utils.createSearchQuery queryTerms}"
  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class DuckDuckGo extends RegexpEngine
  # Example search URL: https://duckduckgo.com/?q=%s
  constructor: -> super [ new RegExp "^https?://([a-z]+\.)?duckduckgo\.com/" ]
  getUrl: (queryTerms) -> "https://duckduckgo.com/ac/?q=#{Utils.createSearchQuery queryTerms}"
  parse: (xhr) ->
    suggestion.phrase for suggestion in JSON.parse xhr.responseText

# A dummy search engine which is guaranteed to match any search URL, but never produces completions.  This
# allows the rest of the logic to be written knowing that there will always be a completion engine match.
class DummyCompletionEngine
  match: -> true
  # We return a useless URL which we know will succeed, but which won't generate any network traffic.
  getUrl: -> chrome.runtime.getURL "content_scripts/vimium.css"
  parse: -> []

completionEngines = [
  Youtube
  Google
  DuckDuckGo
  Wikipedia
  Bing
  Amazon
  DummyCompletionEngine
]

# A note on caching.
# Some completion engines allow caching, and Chrome serves up cached responses to requests (e.g. Google,
# Wikipedia, YouTube).  Others do not (e.g. Bing, DuckDuckGo, Amazon).  A completion engine can set
# @doNotCache to a truthy value to disable caching in cases where it is unnecessary.

CompletionEngines =
  debug: true

  # The amount of time to wait for new requests before launching the HTTP request.  The intention is to cut
  # down on the number of HTTP requests we issue.
  delay: 250

  get: (searchUrl, url, callback) ->
    xhr = new XMLHttpRequest()
    xhr.open "GET", url, true
    xhr.timeout = 1000
    xhr.ontimeout = xhr.onerror = -> callback null
    xhr.send()

    xhr.onreadystatechange = ->
      if xhr.readyState == 4
        console.log xhr.getAllResponseHeaders()
        callback(if xhr.status == 200 then xhr else null)

  # Look up the completion engine for this searchUrl.  Because of DummyCompletionEngine, above, we know there
  # will always be a match.  Imagining that there may be many completion engines, and knowing that this is
  # called for every input event in the vomnibar, we cache the result.
  lookupEngine: (searchUrl) ->
    @engineCache ?= new SimpleCache 30 * 60 * 60 * 1000 # 30 hours (these are small, we can keep them longer).
    if @engineCache.has searchUrl
      @engineCache.get searchUrl
    else
      for engine in completionEngines
        engine = new engine()
        return @engineCache.set searchUrl, engine if engine.match searchUrl

  # This is the main entry point.
  #  - searchUrl is the search engine's URL, e.g. Settings.get("searchUrl"), or a custome search engine's URL.
  #    This is only used as a key for determining the relevant completion engine.
  #  - queryTerms are the query terms.
  #  - callback will be applied to a list of suggestion strings (which may be an empty list, if anything goes
  #    wrong).
  complete: (searchUrl, queryTerms, callback) ->
    @mostRecentHandler = null
    query = queryTerms.join ""

    # We don't complete less then three characters: the results are usually useless.  This also prevents
    # one- and two-character custom search engine keywords from being sent to the default completer (e.g.
    # the initial "w" before typing "w something" for Wikipedia).
    return callback [] unless 3 <= query.length

    # We don't complete regular URLs or Javascript URLs.
    return callback [] if 1 == queryTerms.length and Utils.isUrl query
    return callback [] if Utils.hasJavascriptPrefix query

    # Cache completions.  However, completions depend upon both the searchUrl and the query terms.  So we need
    # to generate a key.  We mix in some junk generated by pwgen. A key clash might be possible, but
    # vanishingly unlikely.
    junk = "//Zi?ei5;o//"
    completionCacheKey = searchUrl + junk + queryTerms.join junk
    @completionCache ?= new SimpleCache 60 * 60 * 1000, 2000 # One hour, 2000 entries.
    if @completionCache.has completionCacheKey
      # We add a short delay, even for a cache hit.  This avoids an ugly flicker when the additional
      # suggestions are posted.  It also makes the vomnibar behave similarly regardless of whether there's a
      # cache hit.
      Utils.setTimeout @delay, =>
        console.log "hit", completionCacheKey if @debug
        callback @completionCache.get completionCacheKey
      return

    fetchSuggestions = (engine, callback) =>
      url = engine.getUrl queryTerms
      query = queryTerms.join(" ").toLowerCase()
      @get searchUrl, url, (xhr = null) =>
        # Parsing the response may fail if we receive an unexpected or an unexpectedly-formatted response.  In
        # all cases, we fall back to the catch clause, below.  Therefore, we "fail safe" in the case of
        # incorrect or out-of-date completion engines.
        try
          suggestions = engine.parse xhr
          # Make sure we really do have an iterable of strings.
          suggestions = (suggestion for suggestion in suggestions when "string" == typeof suggestion)
          # Filter out the query itself. It's not adding anything.
          suggestions = (suggestion for suggestion in suggestions when suggestion.toLowerCase() != query)
          console.log "GET", url if @debug
        catch
          suggestions = []
          # We allow failures to be cached, but remove them after just ten minutes.  This (it is hoped) avoids
          # repeated unnecessary XMLHttpRequest failures over a short period of time.
          removeCompletionCacheKey = => @completionCache.set completionCacheKey, null
          setTimeout removeCompletionCacheKey, 10 * 60 * 1000 # Ten minutes.
          console.log "fail", url if @debug

        callback suggestions

    # We pause in case the user is still typing.
    Utils.setTimeout @delay, handler = @mostRecentHandler = =>
      if handler != @mostRecentHandler # Bail if another completion has begun, or the user is typing.
        console.log "bail", completionCacheKey if @debug
        return callback []
      # Don't allow duplicate identical active requests.  This can happen, for example, when the user enters or
      # removes a space, or when they enter a character and immediately delete it.
      @inTransit ?= {}
      unless @inTransit[completionCacheKey]?.push callback
        queue = @inTransit[completionCacheKey] = []
        engine = @lookupEngine searchUrl
        fetchSuggestions engine, (suggestions) =>
          @completionCache.set completionCacheKey, suggestions unless engine.doNotCache
          callback suggestions
          delete @inTransit[completionCacheKey]
          console.log "callbacks", queue.length, completionCacheKey if @debug and 0 < queue.length
          callback suggestions for callback in queue

  cancel: ->
    console.log "cancel (user is typing)" if @debug and @mostRecentHandler?
    @mostRecentHandler = null

root = exports ? window
root.CompletionEngines = CompletionEngines

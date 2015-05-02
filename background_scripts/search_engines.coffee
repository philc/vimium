
# Each completer implements three functions:
#
#   match:  can this completer be used for this search URL?
#   getUrl: map these query terms to a completion URL.
#   parse:  extract suggestions from the resulting (successful) XMLHttpRequest.
#
class Google
  constructor: ->
  name: "Google"
  match: (searchUrl) ->
    return true if /^https?:\/\/[a-z]+.google.com\//.test searchUrl
    # NOTE(smblott). A  temporary hack, just for me, and just for development. Will be removed.
    return true if /localhost\/.*\/booky/.test searchUrl
    false

  getUrl: (queryTerms) ->
    "http://suggestqueries.google.com/complete/search?ss_protocol=legace&client=toolbar&q=#{Utils.createSearchQuery queryTerms}"

  parse: (xhr, callback) ->
    if suggestions = xhr?.responseXML?.getElementsByTagName "suggestion"
      suggestions =
        for suggestion in suggestions
          continue unless suggestion = suggestion.getAttribute "data"
          suggestion
      callback suggestions
    else
      callback []

# A dummy search engine which is guaranteed to match any search URL, but never produces completions.  This
# allows the rest of the logic to be written knowing that there will be a search engine match.
class DummySearchEngine
  constructor: ->
  name: "Dummy"
  match: -> true
  # We return a useless URL which we know will succeed, but which won't generate any network traffic.
  getUrl: -> chrome.runtime.getURL "content_scripts/vimium.css"
  parse: (_, callback) -> callback []

completionEngines = [ Google, DummySearchEngine ]

SearchEngines =
  cancel: (searchUrl, callback = null) ->
    @requests[searchUrl]?.abort()
    delete @requests[searchUrl]
    callback? null

  # Perform an HTTP GET.
  #   searchUrl is the search engine's URL, e.g. Settings.get("searchUrl").
  #   url is the URL to fetch.
  #   callback will be called with a successful XMLHttpRequest object, or null.
  get: (searchUrl, url, callback) ->
    @requests ?= {} # Maps searchUrls to any outstanding HTTP request for that search engine.
    @cancel searchUrl

    # We cache the results of the most-recent 1000 requests (with a two-hour expiry).
    # FIXME(smblott) Currently we're caching XMLHttpRequest objects, which is wasteful of memory.  It would be
    # better to handle caching at a higher level.
    @requestCache ?= new SimpleCache 2 * 60 * 60 * 1000, 1000

    if @requestCache.has url
      callback @requestCache.get url
      return

    @requests[searchUrl] = xhr = new XMLHttpRequest()
    xhr.open "GET", url, true
    xhr.timeout = 500
    xhr.ontimeout = => @cancel searchUrl, callback
    xhr.onerror = => @cancel searchUrl, callback
    xhr.send()

    xhr.onreadystatechange = =>
      if xhr.readyState == 4
        if xhr.status == 200
          @requests[searchUrl] = null
          callback @requestCache.set url, xhr
        else
          callback null

  # Look up the search-completion engine for this search URL.  Because of DummySearchEngine, above, we know
  # there will always be a match.  Imagining that there may be many search engines, and knowing that this is
  # called for every character entered, we cache the result.
  lookupEngine: (searchUrl) ->
    @engineCache ?= new SimpleCache 24 * 60 * 60 * 1000
    if @engineCache.has searchUrl
      @engineCache.get searchUrl
    else
      for engine in completionEngines
        engine = new engine()
        return @engineCache.set searchUrl, engine if engine.match searchUrl

  # This is the main (actually, the only) entry point.
  #   searchUrl is the search engine's URL, e.g. Settings.get("searchUrl").
  #   queryTerms are the queryTerms.
  #   callback will be applied to a list of suggestion strings (which may be an empty list, if anything goes
  #   wrong).
  complete: (searchUrl, queryTerms, callback) ->
    return callback [] unless 0 < queryTerms.length

    # Don't try to complete general URLs.
    return callback [] if 1 == queryTerms.length and Utils.isUrl queryTerms[0]

    # Don't try to complete Javascrip URLs.
    return callback [] if 0 < queryTerms.length and Utils.hasJavascriptPrefix queryTerms[0]

    engine = @lookupEngine searchUrl
    url = engine.getUrl queryTerms
    @get searchUrl, url, (xhr = null) ->
      if xhr? then engine.parse xhr, callback else callback []

root = exports ? window
root.SearchEngines = SearchEngines

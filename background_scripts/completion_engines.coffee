
# A completion engine provides search suggestions for a search engine.  A search engine is identified by a
# "searchUrl", e.g. Settings.get("searchUrl"), or a custom search engine URL.
#
# Each completion engine defines three functions:
#
#   1. "match" - This takes a searchUrl and returns a boolean indicating whether this completion engine can
#      perform completion for the given search engine.
#
#   2. "getUrl" - This takes a list of query terms (queryTerms) and generates a completion URL, that is, a URL
#      which will provide completions for this completion engine.
#
#   3. "parse" - This takes a successful XMLHttpRequest object (the request has completed successfully), and
#      returns a list of suggestions (a list of strings).  This method is always executed within the context
#      of a try/catch block, so errors do not propagate.
#
# Each new completion engine must be added to the list "CompletionEngines" at the bottom of this file.
#
# The lookup logic which uses these completion engines is in "./completion_search.coffee".
#

# A base class for common regexp-based matching engines.
class RegexpEngine
  constructor: (args...) -> @regexps = args.map (regexp) -> new RegExp regexp
  match: (searchUrl) -> Utils.matchesAnyRegexp @regexps, searchUrl

# Several Google completion engines package XML responses in this way.
class GoogleXMLRegexpEngine extends RegexpEngine
  parse: (xhr) ->
    for suggestion in xhr.responseXML.getElementsByTagName "suggestion"
      continue unless suggestion = suggestion.getAttribute "data"
      suggestion

class Google extends GoogleXMLRegexpEngine
  constructor: (regexps = null) ->
    super regexps ? "^https?://[a-z]+\\.google\\.(com|ie|co\\.uk|ca|com\\.au)/"
    @exampleSearchUrl = "http://www.google.com/search?q=%s"
    @exampleKeyword = "m"

  getUrl: (queryTerms) ->
    Utils.createSearchUrl queryTerms,
      "http://suggestqueries.google.com/complete/search?ss_protocol=legace&client=toolbar&q=%s"

# A wrapper class for Google completions.  This adds prefix terms to the query, and strips those terms from
# the resulting suggestions.  For example, for Google Maps, we add "map of" as a prefix, then strip "map of"
# from the resulting suggestions.
class GoogleWithPrefix extends Google
  constructor: (prefix, args...) ->
    super args...
    prefix = prefix.trim()
    @prefix = "#{prefix} "
    @queryTerms = prefix.split /\s+/
  getUrl: (queryTerms) -> super [ @queryTerms..., queryTerms... ]
  parse: (xhr) ->
    super(xhr)
      .filter (suggestion) => suggestion.startsWith @prefix
      .map (suggestion) => suggestion[@prefix.length..].ltrim()

# For Google Maps, we add the prefix "map of" to the query, and send it to Google's general search engine,
# then strip "map of" from the resulting suggestions.
class GoogleMaps extends GoogleWithPrefix
  constructor: ->
    super "map of", "^https?://[a-z]+\\.google\\.(com|ie|co\\.uk|ca|com\\.au)/maps"
    @exampleSearchUrl = "https://www.google.com/maps?q=%s"
    @exampleKeyword = "m"
    @exampleDescription = "Google maps"

class Youtube extends GoogleXMLRegexpEngine
  constructor: ->
    super "^https?://[a-z]+\\.youtube\\.com/results"
    @exampleSearchUrl = "http://www.youtube.com/results?search_query=%s"
    @exampleKeyword = "y"

  getUrl: (queryTerms) ->
    Utils.createSearchUrl queryTerms,
      "http://suggestqueries.google.com/complete/search?client=youtube&ds=yt&xml=t&q=%s"

class Wikipedia extends RegexpEngine
  constructor: ->
    super "^https?://[a-z]+\\.wikipedia\\.org/"
    @exampleSearchUrl = "http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s"
    @exampleKeyword = "y"

  getUrl: (queryTerms) ->
    Utils.createSearchUrl queryTerms,
      "https://en.wikipedia.org/w/api.php?action=opensearch&format=json&search=%s"

  parse: (xhr) ->
    JSON.parse(xhr.responseText)[1]

class Bing extends RegexpEngine
  constructor: ->
    super "^https?://www\\.bing\\.com/search"
    @exampleSearchUrl = "https://www.bing.com/search?q=%s"
    @exampleKeyword = "b"
  getUrl: (queryTerms) -> Utils.createSearchUrl queryTerms, "http://api.bing.com/osjson.aspx?query=%s"
  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class Amazon extends RegexpEngine
  constructor: ->
    super "^https?://www\\.amazon\\.(com|co\\.uk|ca|com\\.au)/s/"
    @exampleSearchUrl = "http://www.amazon.com/s/?field-keywords=%s"
    @exampleKeyword = "a"
  getUrl: (queryTerms) ->
    Utils.createSearchUrl queryTerms,
      "https://completion.amazon.com/search/complete?method=completion&search-alias=aps&client=amazon-search-ui&mkt=1&q=%s"
  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class DuckDuckGo extends RegexpEngine
  constructor: ->
    super "^https?://([a-z]+\\.)?duckduckgo\\.com/"
    @exampleSearchUrl = "https://duckduckgo.com/?q=%s"
    @exampleKeyword = "d"
  getUrl: (queryTerms) -> Utils.createSearchUrl queryTerms, "https://duckduckgo.com/ac/?q=%s"
  parse: (xhr) ->
    suggestion.phrase for suggestion in JSON.parse xhr.responseText

class Webster extends RegexpEngine
  constructor: ->
    super "^https?://www.merriam-webster.com/dictionary/"
    @exampleSearchUrl = "http://www.merriam-webster.com/dictionary/%s"
    @exampleKeyword = "dw"
    @exampleDescription = "Dictionary"
  getUrl: (queryTerms) -> Utils.createSearchUrl queryTerms, "http://www.merriam-webster.com/autocomplete?query=%s"
  parse: (xhr) -> JSON.parse(xhr.responseText).suggestions

# A dummy search engine which is guaranteed to match any search URL, but never produces completions.  This
# allows the rest of the logic to be written knowing that there will always be a completion engine match.
class DummyCompletionEngine
  dummy: true
  match: -> true
  # We return a useless URL which we know will succeed, but which won't generate any network traffic.
  getUrl: -> chrome.runtime.getURL "content_scripts/vimium.css"
  parse: -> []

# Note: Order matters here.
CompletionEngines = [
  Youtube
  GoogleMaps
  Google
  DuckDuckGo
  Wikipedia
  Bing
  Amazon
  Webster
  DummyCompletionEngine
]

root = exports ? window
root.CompletionEngines = CompletionEngines

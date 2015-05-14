
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
  constructor: (@regexps) ->
  match: (searchUrl) -> Utils.matchesAnyRegexp @regexps, searchUrl

# Several Google completion engines package XML responses in this way.
class GoogleXMLRegexpEngine extends RegexpEngine
  doNotCache: false # true (disbaled, experimental)
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
    Utils.createSearchUrl queryTerms,
      "http://suggestqueries.google.com/complete/search?ss_protocol=legace&client=toolbar&q=%s"

class Youtube extends GoogleXMLRegexpEngine
  # Example search URL: http://www.youtube.com/results?search_query=%s
  constructor: ->
    super [ new RegExp "^https?://[a-z]+\.youtube\.com/results" ]

  getUrl: (queryTerms) ->
    Utils.createSearchUrl queryTerms,
      "http://suggestqueries.google.com/complete/search?client=youtube&ds=yt&xml=t&q=%s"

class Wikipedia extends RegexpEngine
  doNotCache: false # true (disbaled, experimental)
  # Example search URL: http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s
  constructor: ->
    super [ new RegExp "^https?://[a-z]+\.wikipedia\.org/" ]

  getUrl: (queryTerms) ->
    Utils.createSearchUrl queryTerms,
      "https://en.wikipedia.org/w/api.php?action=opensearch&format=json&search=%s"

  parse: (xhr) ->
    JSON.parse(xhr.responseText)[1]

## Does not work...
## class GoogleMaps extends RegexpEngine
##   # Example search URL: https://www.google.com/maps/search/%s
##   constructor: ->
##     super [ new RegExp "^https?://www\.google\.com/maps/search/" ]
##
##   getUrl: (queryTerms) ->
##     "https://www.google.com/s?tbm=map&fp=1&gs_ri=maps&source=hp&suggest=p&authuser=0&hl=en&pf=p&tch=1&ech=2&q=#{Utils.createSearchQuery queryTerms}"
##
##   parse: (xhr) ->
##     data = JSON.parse xhr.responseText
##     []

class Bing extends RegexpEngine
  # Example search URL: https://www.bing.com/search?q=%s
  constructor: -> super [ new RegExp "^https?://www\.bing\.com/search" ]
  getUrl: (queryTerms) -> Utils.createSearchUrl queryTerms, "http://api.bing.com/osjson.aspx?query=%s"
  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class Amazon extends RegexpEngine
  # Example search URL: http://www.amazon.com/s/?field-keywords=%s
  constructor: -> super [ new RegExp "^https?://www\.amazon\.(com|co.uk|ca|com.au)/s/" ]
  getUrl: (queryTerms) ->
    Utils.createSearchUrl queryTerms,
      "https://completion.amazon.com/search/complete?method=completion&search-alias=aps&client=amazon-search-ui&mkt=1&q=%s"
  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class DuckDuckGo extends RegexpEngine
  # Example search URL: https://duckduckgo.com/?q=%s
  constructor: -> super [ new RegExp "^https?://([a-z]+\.)?duckduckgo\.com/" ]
  getUrl: (queryTerms) ->
  getUrl: (queryTerms) -> Utils.createSearchUrl queryTerms, "https://duckduckgo.com/ac/?q=%s"
  parse: (xhr) ->
    suggestion.phrase for suggestion in JSON.parse xhr.responseText

class Webster extends RegexpEngine
  # Example search URL: http://www.merriam-webster.com/dictionary/%s
  constructor: -> super [ new RegExp "^https?://www.merriam-webster.com/dictionary/" ]
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

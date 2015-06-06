
# A completion engine provides search suggestions for a custom search engine.  A custom search engine is
# identified by a "searchUrl".  An "engineUrl" is used for fetching suggestions, whereas a "searchUrl" is used
# for the actual search itself.
#
# Each completion engine defines:
#
#   1. An "engineUrl". This is the URL to use for search completions and is passed as the option "engineUrl"
#      to the "BaseEngine" constructor.
#
#   2. One or more regular expressions which define the custom search engine URLs for which the completion
#      engine will be used. This is passed as the "regexps" option to the "BaseEngine" constructor.
#
#   3. A "parse" function. This takes a successful XMLHttpRequest object (the request has completed
#      successfully), and returns a list of suggestions (a list of strings).  This method is always executed
#      within the context of a try/catch block, so errors do not propagate.
#
#   4. For documentation only, each completion engine *must* and example custom search engine.  The example
#      must include an example "keyword" and and example "searchUrl", and may include and example
#      "description".
#
# Each new completion engine must be added to the list "CompletionEngines" at the bottom of this file.
#
# The lookup logic which uses these completion engines is in "./completion_search.coffee".
#

# A base class for common regexp-based matching engines. "options" must define:
#   options.engineUrl: the URL to use for the completion engine. This must be a string.
#   options.regexps: one or regular expressions.  This may either a single string or a list of strings.
#   options.example: an example object containing at least "keyword" and "searchUrl", and optional "description".
class BaseEngine
  constructor: (options) ->
    extend this, options
    @regexps = [ @regexps ] if "string" == typeof @regexps
    @regexps = @regexps.map (regexp) -> new RegExp regexp

  match: (searchUrl) -> Utils.matchesAnyRegexp @regexps, searchUrl
  getUrl: (queryTerms) -> Utils.createSearchUrl queryTerms, @engineUrl

# Several Google completion engines package responses as XML. This parses such XML.
class GoogleXMLBaseEngine extends BaseEngine
  parse: (xhr) ->
    for suggestion in xhr.responseXML.getElementsByTagName "suggestion"
      continue unless suggestion = suggestion.getAttribute "data"
      suggestion

class Google extends GoogleXMLBaseEngine
  constructor: (regexps = null) ->
    super
      engineUrl: "http://suggestqueries.google.com/complete/search?ss_protocol=legace&client=toolbar&q=%s"
      regexps: regexps ? "^https?://[a-z]+\\.google\\.(com|ie|co\\.uk|ca|com\\.au)/"
      example:
        searchUrl: "http://www.google.com/search?q=%s"
        keyword: "g"

## # A wrapper class for Google completions.  This adds prefix terms to the query, and strips those terms from
## # the resulting suggestions.  For example, for Google Maps, we add "map of" as a prefix, then strip "map of"
## # from the resulting suggestions.
## class GoogleWithPrefix extends Google
##   constructor: (prefix, args...) ->
##     super args...
##     prefix = prefix.trim()
##     @prefix = "#{prefix} "
##     @queryTerms = prefix.split /\s+/
##   getUrl: (queryTerms) -> super [ @queryTerms..., queryTerms... ]
##   parse: (xhr) ->
##     super(xhr)
##       .filter (suggestion) => suggestion.startsWith @prefix
##       .map (suggestion) => suggestion[@prefix.length..].ltrim()
##
## # For Google Maps, we add the prefix "map of" to the query, and send it to Google's general search engine,
## # then strip "map of" from the resulting suggestions.
## class GoogleMaps extends GoogleWithPrefix
##   constructor: ->
##     super "map of", "^https?://[a-z]+\\.google\\.(com|ie|co\\.uk|ca|com\\.au)/maps"
##     @exampleSearchUrl = "https://www.google.com/maps?q=%s"
##     @exampleKeyword = "m"
##     @exampleDescription = "Google maps"

class Youtube extends GoogleXMLBaseEngine
  constructor: ->
    super
      engineUrl: "http://suggestqueries.google.com/complete/search?client=youtube&ds=yt&xml=t&q=%s"
      regexps: "^https?://[a-z]+\\.youtube\\.com/results"
      example:
        searchUrl: "http://www.youtube.com/results?search_query=%s"
        keyword: "y"

class Wikipedia extends BaseEngine
  constructor: ->
    super
      engineUrl: "https://en.wikipedia.org/w/api.php?action=opensearch&format=json&search=%s"
      regexps: "^https?://[a-z]+\\.wikipedia\\.org/"
      example:
        searchUrl: "http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s"
        keyword: "w"

  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class Bing extends BaseEngine
  constructor: ->
    super
      engineUrl: "http://api.bing.com/osjson.aspx?query=%s"
      regexps: "^https?://www\\.bing\\.com/search"
      example:
        searchUrl: "https://www.bing.com/search?q=%s"
        keyword: "b"

  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class Amazon extends BaseEngine
  constructor: ->
    super
      engineUrl: "https://completion.amazon.com/search/complete?method=completion&search-alias=aps&client=amazon-search-ui&mkt=1&q=%s"
      regexps: "^https?://www\\.amazon\\.(com|co\\.uk|ca|com\\.au)/s/"
      example:
        searchUrl: "http://www.amazon.com/s/?field-keywords=%s"
        keyword: "a"

  parse: (xhr) -> JSON.parse(xhr.responseText)[1]

class DuckDuckGo extends BaseEngine
  constructor: ->
    super
      engineUrl: "https://duckduckgo.com/ac/?q=%s"
      regexps: "^https?://([a-z]+\\.)?duckduckgo\\.com/"
      example:
        searchUrl: "https://duckduckgo.com/?q=%s"
        keyword: "d"

  parse: (xhr) ->
    suggestion.phrase for suggestion in JSON.parse xhr.responseText

class Webster extends BaseEngine
  constructor: ->
    super
      engineUrl: "http://www.merriam-webster.com/autocomplete?query=%s"
      regexps: "^https?://www.merriam-webster.com/dictionary/"
      example:
        searchUrl: "http://www.merriam-webster.com/dictionary/%s"
        keyword: "dw"
        description: "Dictionary"

  parse: (xhr) -> JSON.parse(xhr.responseText).suggestions

# A dummy search engine which is guaranteed to match any search URL, but never produces completions.  This
# allows the rest of the logic to be written knowing that there will always be a completion engine match.
class DummyCompletionEngine extends BaseEngine
  constructor: ->
    super
      regexps: "."
      dummy: true

# Note: Order matters here.
CompletionEngines = [
  Youtube
  # GoogleMaps
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

# Only pass events to the handler if they are marked as trusted by the browser.
# This is kept in the global namespace for brevity and ease of use.
window.forTrusted ?= (handler) -> (event) ->
  if event?.isTrusted
    handler.apply this, arguments
  else
    true

browserInfo = browser?.runtime?.getBrowserInfo?()

Utils =
  isFirefox: do ->
    # NOTE(mrmr1993): This test only works in the background page, this is overwritten by isEnabledForUrl for
    # content scripts.
    isFirefox = false
    browserInfo?.then? (browserInfo) ->
      isFirefox = browserInfo?.name == "Firefox"
    -> isFirefox
  firefoxVersion: do ->
    # NOTE(mrmr1993): This only works in the background page.
    ffVersion = undefined
    browserInfo?.then? (browserInfo) ->
      ffVersion = browserInfo?.version
    -> ffVersion
  getCurrentVersion: ->
    chrome.runtime.getManifest().version

  # Returns true whenever the current page (or the page supplied as an argument) is from the extension's
  # origin (and thus can access the extension's localStorage).
  isExtensionPage: (win = window) -> try win.document.location?.origin + "/" == chrome.extension.getURL ""

  # Returns true whenever the current page is the extension's background page.
  isBackgroundPage: -> @isExtensionPage() and chrome.extension.getBackgroundPage?() == window

  # Escape all special characters, so RegExp will parse the string 'as is'.
  # Taken from http://stackoverflow.com/questions/3446170/escape-string-for-use-in-javascript-regex
  escapeRegexSpecialCharacters: do ->
    escapeRegex = /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g
    (str) -> str.replace escapeRegex, "\\$&"

  escapeHtml: (string) -> string.replace(/</g, "&lt;").replace(/>/g, "&gt;")

  # Generates a unique ID
  createUniqueId: do ->
    id = 0
    -> id += 1

  hasChromePrefix: do ->
    chromePrefixes = [ "about:", "view-source:", "extension:", "chrome-extension:", "data:" ]
    (url) ->
      for prefix in chromePrefixes
        return true if url.startsWith prefix
      false

  hasJavascriptPrefix: (url) ->
    url.startsWith "javascript:"

  hasFullUrlPrefix: do ->
    urlPrefix = new RegExp "^[a-z][-+.a-z0-9]{2,}://."
    (url) -> urlPrefix.test url

  # Decode valid escape sequences in a URI.  This is intended to mimic the best-effort decoding
  # Chrome itself seems to apply when a Javascript URI is enetered into the omnibox (or clicked).
  # See https://code.google.com/p/chromium/issues/detail?id=483000, #1611 and #1636.
  decodeURIByParts: (uri) ->
    uri.split(/(?=%)/).map((uriComponent) ->
      try
        decodeURIComponent uriComponent
      catch
        uriComponent
    ).join ""

  # Completes a partial URL (without scheme)
  createFullUrl: (partialUrl) ->
    if @hasFullUrlPrefix(partialUrl) then partialUrl else ("http://" + partialUrl)

  # Tries to detect if :str is a valid URL.
  isUrl: (str) ->
    # Must not contain spaces
    return false if ' ' in str

    # Starts with a scheme: URL
    return true if @hasFullUrlPrefix str

    # More or less RFC compliant URL host part parsing. This should be sufficient for our needs
    urlRegex = new RegExp(
      '^(?:([^:]+)(?::([^:]+))?@)?' + # user:password (optional) => \1, \2
      '([^:]+|\\[[^\\]]+\\])'       + # host name (IPv6 addresses in square brackets allowed) => \3
      '(?::(\\d+))?$'                 # port number (optional) => \4
      )

    # Official ASCII TLDs that are longer than 3 characters + inofficial .onion TLD used by TOR
    longTlds = ['arpa', 'asia', 'coop', 'info', 'jobs', 'local', 'mobi', 'museum', 'name', 'onion']

    specialHostNames = ['localhost']

    # Try to parse the URL into its meaningful parts. If matching fails we're pretty sure that we don't have
    # some kind of URL here.
    match = urlRegex.exec (str.split '/')[0]
    return false unless match
    hostName = match[3]

    # Allow known special host names
    return true if hostName in specialHostNames

    # Allow IPv6 addresses (need to be wrapped in brackets as required by RFC). It is sufficient to check for
    # a colon, as the regex wouldn't match colons in the host name unless it's an v6 address
    return true if ':' in hostName

    # At this point we have to make a decision. As a heuristic, we check if the input has dots in it. If yes,
    # and if the last part could be a TLD, treat it as an URL
    dottedParts = hostName.split '.'

    if dottedParts.length > 1
      lastPart = dottedParts.pop()
      return true if 2 <= lastPart.length <= 3 or lastPart in longTlds

    # Allow IPv4 addresses
    return true if /^(\d{1,3}\.){3}\d{1,3}$/.test hostName

    # Fallback: no URL
    return false

  # Map a search query to its URL encoded form. The query may be either a string or an array of strings.
  # E.g. "BBC Sport" -> "BBC+Sport".
  createSearchQuery: (query) ->
    query = query.split(/\s+/) if typeof(query) == "string"
    query.map(encodeURIComponent).join "+"

  # Create a search URL from the given :query (using either the provided search URL, or the default one).
  # It would be better to pull the default search engine from chrome itself.  However, chrome does not provide
  # an API for doing so.
  createSearchUrl: (query, searchUrl = Settings.get("searchUrl")) ->
    searchUrl += "%s" unless 0 <= searchUrl.indexOf "%s"
    searchUrl.replace /%s/g, @createSearchQuery query

  # Extract a query from url if it appears to be a URL created from the given search URL.
  # For example, map "https://www.google.ie/search?q=star+wars&foo&bar" to "star wars".
  extractQuery: do =>
    queryTerminator = new RegExp "[?&#/]"
    httpProtocolRegexp = new RegExp "^https?://"
    (searchUrl, url) ->
      url = url.replace httpProtocolRegexp
      searchUrl = searchUrl.replace httpProtocolRegexp
      [ searchUrl, suffixTerms... ] = searchUrl.split "%s"
      # We require the URL to start with the search URL.
      return null unless url.startsWith searchUrl
      # We require any remaining terms in the search URL to also be present in the URL.
      for suffix in suffixTerms
        return null unless 0 <= url.indexOf suffix
      # We use try/catch because decodeURIComponent can throw an exception.
      try
          url[searchUrl.length..].split(queryTerminator)[0].split("+").map(decodeURIComponent).join " "
      catch
        null

  # Converts :string into a Google search if it's not already a URL. We don't bother with escaping characters
  # as Chrome will do that for us.
  convertToUrl: (string) ->
    string = string.trim()

    # Special-case about:[url], view-source:[url] and the like
    if Utils.hasChromePrefix string
      string
    else if Utils.hasJavascriptPrefix string
      # In Chrome versions older than 46.0.2467.2, encoded javascript URIs weren't handled correctly.
      if Utils.haveChromeVersion "46.0.2467.2" then string else Utils.decodeURIByParts string
    else if Utils.isUrl string
      Utils.createFullUrl string
    else
      Utils.createSearchUrl string

  # detects both literals and dynamically created strings
  isString: (obj) -> typeof obj == 'string' or obj instanceof String

  # Transform "zjkjkabz" into "abjkz".
  distinctCharacters: (str) ->
    chars = str.split("").sort()
    (ch for ch, index in chars when index == 0 or ch != chars[index-1]).join ""

  # Compares two version strings (e.g. "1.1" and "1.5") and returns
  # -1 if versionA is < versionB, 0 if they're equal, and 1 if versionA is > versionB.
  compareVersions: (versionA, versionB) ->
    versionA = versionA.split(".")
    versionB = versionB.split(".")
    for i in [0...(Math.max(versionA.length, versionB.length))]
      a = parseInt(versionA[i] || 0, 10)
      b = parseInt(versionB[i] || 0, 10)
      if (a < b)
        return -1
      else if (a > b)
        return 1
    0

  # True if the current Chrome version is at least the required version.
  haveChromeVersion: (required) ->
    chromeVersion = navigator.appVersion.match(/Chrom(e|ium)\/(.*?) /)?[2]
    chromeVersion and 0 <= Utils.compareVersions chromeVersion, required

  # Zip two (or more) arrays:
  #   - Utils.zip([ [a,b], [1,2] ]) returns [ [a,1], [b,2] ]
  #   - Length of result is `arrays[0].length`.
  #   - Adapted from: http://stackoverflow.com/questions/4856717/javascript-equivalent-of-pythons-zip-function
  zip: (arrays) ->
    arrays[0].map (_,i) ->
      arrays.map( (array) -> array[i] )

  # locale-sensitive uppercase detection
  hasUpperCase: (s) -> s.toLowerCase() != s

  # Does string match any of these regexps?
  matchesAnyRegexp: (regexps, string) ->
    for re in regexps
      return true if re.test string
    false

  # Convenience wrapper for setTimeout (with the arguments around the other way).
  setTimeout: (ms, func) -> setTimeout func, ms

  # Like Nodejs's nextTick.
  nextTick: (func) -> @setTimeout 0, func

  # Make an idempotent function.
  makeIdempotent: (func) ->
    (args...) -> ([previousFunc, func] = [func, null])[0]? args...

  monitorChromeStorage: (key, setter) ->
    # NOTE: "?" here for the tests.
    chrome?.storage.local.get key, (obj) =>
      setter obj[key] if obj[key]?
      chrome.storage.onChanged.addListener (changes, area) =>
        setter changes[key].newValue if changes[key]?.newValue?

# This creates a new function out of an existing function, where the new function takes fewer arguments. This
# allows us to pass around functions instead of functions + a partial list of arguments.
Function::curry = ->
  fixedArguments = Array.copy(arguments)
  fn = this
  -> fn.apply(this, fixedArguments.concat(Array.copy(arguments)))

Array.copy = (array) -> Array.prototype.slice.call(array, 0)

String::startsWith = (str) -> @indexOf(str) == 0
String::ltrim = -> @replace /^\s+/, ""
String::rtrim = -> @replace /\s+$/, ""
String::reverse = -> @split("").reverse().join ""

globalRoot = window ? global
globalRoot.extend = (hash1, hash2) ->
  for own key of hash2
    hash1[key] = hash2[key]
  hash1

# A simple cache. Entries used within two expiry periods are retained, otherwise they are discarded.
# At most 2 * @entries entries are retained.
class SimpleCache
  # expiry: expiry time in milliseconds (default, one hour)
  # entries: maximum number of entries in @cache (there may be up to this many entries in @previous, too)
  constructor: (@expiry = 60 * 60 * 1000, @entries = 1000) ->
    @cache = {}
    @previous = {}
    @lastRotation = new Date()

  has: (key) ->
    @rotate()
    (key of @cache) or key of @previous

  # Set value, and return that value.  If value is null, then delete key.
  set: (key, value = null) ->
    @rotate()
    delete @previous[key]
    if value?
      @cache[key] = value
    else
      delete @cache[key]
      null

  get: (key) ->
    @rotate()
    if key of @cache
      @cache[key]
    else if key of @previous
      @cache[key] = @previous[key]
      delete @previous[key]
      @cache[key]
    else
      null

  rotate: (force = false) ->
    Utils.nextTick =>
      if force or @entries < Object.keys(@cache).length or @expiry < new Date() - @lastRotation
        @lastRotation = new Date()
        @previous = @cache
        @cache = {}

  clear: ->
    @rotate true
    @rotate true

# This is a simple class for the common case where we want to use some data value which may be immediately
# available, or for which we may have to wait.  It implements a use-immediately-or-wait queue, and calls the
# fetch function to fetch the data asynchronously.
class AsyncDataFetcher
  constructor: (fetch) ->
    @data = null
    @queue = []
    Utils.nextTick =>
      fetch (@data) =>
        callback @data for callback in @queue
        @queue = null

  use: (callback) ->
    if @data? then callback @data else @queue.push callback

# This takes a list of jobs (functions) and runs them, asynchronously.  Functions queued with @onReady() are
# run once all of the jobs have completed.
class JobRunner
  constructor: (@jobs) ->
    @fetcher = new AsyncDataFetcher (callback) =>
      for job in @jobs
        do (job) =>
          Utils.nextTick =>
            job =>
              @jobs = @jobs.filter (j) -> j != job
              callback true if @jobs.length == 0

  onReady: (callback) ->
    @fetcher.use callback

root = exports ? (window.root ?= {})
root.Utils = Utils
root.SimpleCache = SimpleCache
root.AsyncDataFetcher = AsyncDataFetcher
root.JobRunner = JobRunner
unless exports?
  root.extend = extend
  extend window, root

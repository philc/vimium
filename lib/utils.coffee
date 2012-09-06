Utils =
  getCurrentVersion: ->
    # Chromium #15242 will make this XHR request to access the manifest
    # unnecessary
    manifestRequest = new XMLHttpRequest()
    manifestRequest.open("GET", chrome.extension.getURL("manifest.json"), false)
    manifestRequest.send(null)
    JSON.parse(manifestRequest.responseText).version

  # Takes a dot-notation object string and call the function
  # that it points to with the correct value for 'this'.
  invokeCommandString: (str, argArray) ->
    components = str.split('.')
    obj = window
    for component in components[0...-1]
      obj = obj[component]
    func = obj[components.pop()]
    func.apply(obj, argArray)

  # Creates a single DOM element from :html
  createElementFromHtml: (html) ->
    tmp = document.createElement("div")
    tmp.innerHTML = html
    tmp.firstChild

  escapeHtml: (string) -> string.replace(/</g, "&lt;").replace(/>/g, "&gt;")

  # Generates a unique ID
  createUniqueId: do ->
    id = 0
    -> id += 1

  hasChromePrefix: (url) ->
    chromePrefixes = [ 'about', 'view-source' ]
    for prefix in chromePrefixes
      return true if url.startsWith prefix
    false

  # Completes a partial URL (without scheme)
  createFullUrl: (partialUrl) ->
    unless /^[a-z]{3,}:\/\//.test partialUrl
      "http://" + partialUrl
    else
      partialUrl

  # Tries to detect if :str is a valid URL.
  isUrl: (str) ->
    # Starts with a scheme: URL
    return true if /^[a-z]{3,}:\/\//.test str

    # Must not contain spaces
    return false if ' ' in str

    # More or less RFC compliant URL host part parsing. This should be sufficient for our needs
    urlRegex = new RegExp(
      '^(?:([^:]+)(?::([^:]+))?@)?' + # user:password (optional) => \1, \2
      '([^:]+|\\[[^\\]]+\\])' + # host name (IPv6 addresses in square brackets allowed) => \3
      '(?::(\\d+))?$' # port number (optional) => \4
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

  # Creates a search URL from the given :query.
  createSearchUrl: (query) ->
    # Escape explicitely to encode characters like "+" correctly
    "http://www.google.com/search?q=" + encodeURIComponent(query)

  # Converts :string into a Google search if it's not already a URL. We don't bother with escaping characters
  # as Chrome will do that for us.
  convertToUrl: (string) ->
    string = string.trim()

    # Special-case about:[url] and view-source:[url]
    if Utils.hasChromePrefix string
      string
    else if Utils.isUrl string
      Utils.createFullUrl string
    else
      Utils.createSearchUrl string

# This creates a new function out of an existing function, where the new function takes fewer arguments. This
# allows us to pass around functions instead of functions + a partial list of arguments.
Function::curry = ->
  fixedArguments = Array.copy(arguments)
  fn = this
  -> fn.apply(this, fixedArguments.concat(Array.copy(arguments)))

Array.copy = (array) -> Array.prototype.slice.call(array, 0)

String::startsWith = (str) -> @indexOf(str) == 0

globalRoot = window ? global
globalRoot.extend = (hash1, hash2) ->
  for key of hash2
    hash1[key] = hash2[key]
  hash1

root = exports ? window
root.Utils = Utils

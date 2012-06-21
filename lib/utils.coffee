Utils =
  getCurrentVersion: ->
    # Chromium #15242 will make this XHR request to access the manifest unnecessary.
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
  createUniqueId: (->
    id = 0
    return -> id += 1
  )()

  hasChromePrefix: (url) ->
    chromePrefixes = [ 'about', 'view-source' ]
    for prefix in chromePrefixes
      return true if url.startsWith prefix
    false

  # Completes a partial URL (without scheme)
  createFullUrl: (partialUrl) ->
    if (!/^[a-z]{3,}:\/\//.test(partialUrl))
      "http://" + partialUrl
    else
      partialUrl

  # Tries to detect, whether :str is a valid URL.
  isUrl: (str) ->
    # more or less RFC compliant URL host part parsing. This should be sufficient
    # for our needs
    urlRegex = new RegExp(
      '^(?:([^:]+)(?::([^:]+))?@)?' +   # user:password (optional)     => \1, \2
      '([^:]+|\\[[^\\]]+\\])'       +   # host name (IPv6 addresses in square brackets allowed) => \3
      '(?::(\\d+))?$'                   # port number (optional)       => \4
      )

    # these are all official ASCII TLDs that are longer than 3 characters
    # (including the inofficial .onion TLD used by TOR)
    longTlds = [ 'arpa', 'asia', 'coop', 'info', 'jobs', 'local', 'mobi', 'museum', 'name', 'onion' ]

    # are there more?
    specialHostNames = [ 'localhost' ]

    # it starts with a scheme, so it's definitely an URL
    if (/^[a-z]{3,}:\/\//.test(str))
      return true

    # spaces => definitely not a valid URL
    if (str.indexOf(' ') >= 0)
      return false

    # assuming that this is an URL, try to parse it into its meaningful parts. If matching fails, we're
    # pretty sure that we don't have some kind of URL here.
    match = urlRegex.exec(str.split('/')[0])
    if (!match)
      return false
    hostname = match[3]

    # allow known special host names
    if (specialHostNames.indexOf(hostname) >= 0)
      return true

    # allow IPv6 addresses (need to be wrapped in brackets, as required by RFC).  It is sufficient to check
    # for a colon here, as the regex wouldn't match colons in the host name unless it's an v6 address
    if (hostname.indexOf(':') >= 0)
      return true

    # at this point we have to make a decision. As a heuristic, we check if the input has dots in it. If
    # yes, and if the last part could be a TLD, treat it as an URL.
    dottedParts = hostname.split('.')
    lastPart = dottedParts[dottedParts.length-1]
    if (dottedParts.length > 1 && ((lastPart.length >= 2 && lastPart.length <= 3) ||
        longTlds.indexOf(lastPart) >= 0))
      return true

    # also allow IPv4 addresses
    if (/^(\d{1,3}\.){3}\d{1,3}$/.test(hostname))
      return true

    # fallback: no URL
    return false

  # Creates a search URL from the given :query.
  createSearchUrl: (query) ->
    # we need to escape explictely to encode characters like "+" correctly
    "http://www.google.com/search?q=" + encodeURIComponent(query)

  # Converts :string into a google search if it's not already a URL.
  # We don't bother with escaping characters as Chrome will do that for us.
  convertToUrl: (string) ->
    string = string.trim()
    # special-case about:[url] and view-source:[url]
    if Utils.hasChromePrefix string then string
    else
      if (Utils.isUrl(string)) then Utils.createFullUrl(string) else Utils.createSearchUrl(string)

# This creates a new function out of an existing function, where the new function takes fewer arguments.
# This allows us to pass around functions instead of functions + a partial list of arguments.
Function.prototype.curry = ->
  fixedArguments = Array.copy(arguments)
  fn = this
  -> fn.apply(this, fixedArguments.concat(Array.copy(arguments)))

Array.copy = (array) -> Array.prototype.slice.call(array, 0)

String::startsWith = (str) -> @indexOf(str) == 0

# A very simple method for defining a new class (constructor and methods) using a single hash.
# No support for inheritance is included because we really shouldn't need it.
# TODO(philc): remove this.
Class =
  extend: (properties) ->
    newClass = ->
      this.init.apply(this, arguments) if (this.init)
      null
    newClass.prototype = properties
    newClass.constructor = newClass
    newClass

globalRoot = if window? then window else global
globalRoot.extend = (hash1, hash2) ->
  for key of hash2
    hash1[key] = hash2[key]
  hash1

root = exports ? window
root.Utils = Utils
root.Class = Class

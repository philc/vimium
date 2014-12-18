Utils =
  getCurrentVersion: ->
    chrome.runtime.getManifest().version

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

  hasChromePrefix: do ->
    chromePrefixes = [ "about:", "view-source:", "extension:", "chrome-extension:", "data:" ]
    (url) ->
      if 0 < url.indexOf ":"
        for prefix in chromePrefixes
          return true if url.startsWith prefix
      false

  hasFullUrlPrefix: do ->
    urlPrefix = new RegExp "^[a-z]{3,}://."
    (url) -> urlPrefix.test url

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

  # Creates a search URL from the given :query.
  createSearchUrl: (query) ->
    # it would be better to pull the default search engine from chrome itself,
    # but it is not clear if/how that is possible
    Settings.get("searchUrl") + encodeURIComponent(query)

  # Converts :string into a Google search if it's not already a URL. We don't bother with escaping characters
  # as Chrome will do that for us.
  convertToUrl: (string) ->
    string = string.trim()

    # Special-case about:[url], view-source:[url] and the like
    if Utils.hasChromePrefix string
      string
    else if Utils.isUrl string
      Utils.createFullUrl string
    else
      Utils.createSearchUrl string

  # detects both literals and dynamically created strings
  isString: (obj) -> typeof obj == 'string' or obj instanceof String


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

  # Zip two (or more) arrays:
  #   - Utils.zip([ [a,b], [1,2] ]) returns [ [a,1], [b,2] ]
  #   - Length of result is `arrays[0].length`.
  #   - Adapted from: http://stackoverflow.com/questions/4856717/javascript-equivalent-of-pythons-zip-function
  zip: (arrays) ->
    arrays[0].map (_,i) ->
      arrays.map( (array) -> array[i] )

  # locale-sensitive uppercase detection
  hasUpperCase: (s) -> s.toLowerCase() != s

  # Create a rect given the top left and bottom right corners.
  createRect: (x1, y1, x2, y2) ->
    bottom: y2
    top: y1
    left: x1
    right: x2
    width: x2 - x1
    height: y2 - y1

  # Translate a rect by x horizontally and y vertically.
  shiftRect: (rect, x, y) ->
    bottom: rect.bottom + y
    top: rect.top + y
    left: rect.left + x
    right: rect.right + x
    width: rect.width
    height: rect.height

  # Subtract rect2 from rect1, returning an array of rects which are in rect1 but not rect2.
  subtractRect: (rect1, rect2_) ->
    # Bound rect2 by rect1
    rect2 = {}
    rect2 = @createRect(
      Math.max(rect1.left, rect2_.left),
      Math.max(rect1.top, rect2_.top),
      Math.min(rect1.right, rect2_.right),
      Math.min(rect1.bottom, rect2_.bottom)
    )

    # If bounding rect2 has made the width or height negative, rect1 does not contain rect2.
    return [rect1] if rect2.width < 0 or rect2.height < 0

    #
    # All the possible rects, in the order
    # +-+-+-+
    # |1|2|3|
    # +-+-+-+
    # |4| |5|
    # +-+-+-+
    # |6|7|8|
    # +-+-+-+
    # where the outer rectangle is rect1 and the inner rectangle is rect 2. Note that the rects may be of
    # width or height 0.
    #
    rects = [
      # Top row.
      @createRect rect1.left, rect1.top, rect2.left, rect2.top
      @createRect rect2.left, rect1.top, rect2.right, rect2.top
      @createRect rect2.right, rect1.top, rect1.right, rect2.top
      # Middle row.
      @createRect rect1.left, rect2.top, rect2.left, rect2.bottom
      @createRect rect2.right, rect2.top, rect1.right, rect2.bottom
      # Bottom row.
      @createRect rect1.left, rect2.bottom, rect2.left, rect1.bottom
      @createRect rect2.left, rect2.bottom, rect2.right, rect1.bottom
      @createRect rect2.right, rect2.bottom, rect1.right, rect1.bottom
    ]

    rects.filter (rect) -> rect.height > 0 and rect.width > 0

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

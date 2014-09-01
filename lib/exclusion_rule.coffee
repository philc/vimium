root = exports ? window

# An ExclusionRule represents a single exclusion rule, composed of a pattern (against which URLs are matched),
# and a set keys which should be passed through to the underlying web page.  Such "passKeys" are represented
# as strings of characters. If passKeys is falsy (the empty string), then Vimium is wholly disabled.
class root.ExclusionRule

  constructor: (pattern,passKeys="") ->
    @pattern = pattern.trim()   # type string
    @passKeys = passKeys.trim() # type string
    @regexp = null              # type RegExp

  matchUrl: (url) ->
    # The user can add "*" to the URL which means ".*".
    @regexp = new RegExp("^" + @pattern.replace(/\*/g, ".*") + "$") unless @regexp
    return url.match(@regexp)

  getPattern: -> @pattern
  getPassKeys: -> @passKeys

  # Static method.
  # TODO (smblott): This currently only works for unmodified keys (so not for '<c-a>', or the like).
  @isPassKey: (passKeys,keyChar) ->
    passKeys and 0 <= passKeys.indexOf keyChar

  # Static method.
  # Parse a flat, legacy rule (a string).
  # Return either a new ExclusionRule or null (if rule is empty, or a comment).
  @parseLegacy: (rule) ->
    rule = rule.trim()
    if rule
      parse = rule.split(/\s+/)
      if parse[0].indexOf("#") != 0 and parse[0].indexOf('"') != 0
        return new ExclusionRule(parse[0],parse[1..].join(""))
    return null

  #
  # DOM handling for the options page...
  #
  buildInputContainer: (enableSaveButton,value,placeholder,cls) ->
    input = document.createElement("input")
    input.setAttribute("placeholder",placeholder)
    input.type = "text"
    input.value = value
    input.className = cls
    input.addEventListener "keyup", enableSaveButton, false
    input.addEventListener "change", enableSaveButton, false
    container = document.createElement("td")
    container.appendChild(input)
    container

  buildRuleRow: (enableSaveButton) ->
    pattern = @buildInputContainer(enableSaveButton,@pattern,"Pattern","pattern")
    passKeys = @buildInputContainer(enableSaveButton,@passKeys,"Disabled","passKeys")
    row = document.createElement("tr")
    remove = document.createElement("input")
    remove.type = "button"
    remove.value = "\u2716" # A cross.
    remove.className = "exclusionRemoveButton"
    remove.addEventListener "click", ->
      row.parentNode.removeChild(row)
      enableSaveButton()
    row.appendChild(pattern)
    row.appendChild(passKeys)
    row.appendChild(remove)
    row.className = "exclusionRow"
    # NOTE: Since the order of exclusions matters, it would be nice to have "Move Up" and "Move Down" buttons,
    # too.  But the options page is getting pretty cramped already.
    row

  # Static method.
  # Returns new ExclusionRule. Or null, if the pattern is empty.
  @mkRuleFromRow: (element) ->
    patternElement = element.firstChild
    passKeysElement = patternElement.nextSibling
    pattern = patternElement.firstChild.value
    passKeys = passKeysElement.firstChild.value
    if patternElement then new ExclusionRule(pattern,passKeys) else null


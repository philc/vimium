root = exports ? window

# An ExclusionRule represents a single exclusion rule.  Each such exclusion rule is composed of a pattern
# (against which URLs are matched), and a set keys which should be passed through to be handled by the
# underlying web page.  Such "passKeys" are represented as a sting of characters.. If passKeys is falsy (the
# empty string), then Vimium is wholly disabled.
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
  # Only used in content scripts.  But defined here to keep all of the exclusion logic together.
  # TODO (smblott): This currently only works for unmodified keys (so not for '<c-a>', or the like).
  @isPassKey: (passKeys,keyChar) ->
    passKeys and 0 <= passKeys.indexOf keyChar

  # Static method.
  # Parse a flat, legacy rule (a string).
  # Return either a new ExclusionRule or null (if rule is empty, or a comment).
  @parseLegacy: (rule) ->
    rule = rule.trim()
    return null if rule.length == 0
    parse = rule.split(/\s+/)
    return null if parse[0].indexOf("#") == 0 or parse[0].indexOf('"') == 0
    return new ExclusionRule(parse[0],parse[1..].join(""))

  # Return the flat, legacy representation of this rule.
  toString: ->
    if @passKeys then @pattern + " " + @passKeys else @pattern


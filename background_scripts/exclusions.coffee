root = exports ? window

RegexpCache =
  cache: {}
  clear: -> @cache = {}
  get: (pattern) ->
    if regexp = @cache[pattern]
      regexp
    else
      @cache[pattern] =
        # We use try/catch to ensure that a broken regexp doesn't wholly cripple Vimium.
        try
          new RegExp("^" + pattern.replace(/\*/g, ".*") + "$")
        catch
          /^$/ # Match the empty string.

# The Exclusions class manages the exclusion rule setting.
# An exclusion is an object with two attributes: pattern and passKeys.
# The exclusions are an array of such objects.

root.Exclusions = Exclusions =
  # Make RegexpCache, which is required on the page popup, accessible via the Exclusions object.
  RegexpCache: RegexpCache

  rules: Settings.get("exclusionRules")

  # Merge the matching rules for URL, or null.  In the normal case, we use the configured @rules; hence, this
  # is the default.  However, when called from the page popup, we are testing what effect candidate new rules
  # would have on the current tab.  In this case, the candidate rules are provided by the caller.
  getRule: (url, rules=@rules) ->
    matches = (rule for rule in rules when rule.pattern and 0 <= url.search(RegexpCache.get(rule.pattern)))
    # An absolute exclusion rule (with no passKeys) takes priority.
    for rule in matches
      return rule unless rule.passKeys
    # Strip whitespace from all matching passKeys strings, and join them together.
    passKeys = (rule.passKeys.split(/\s+/).join "" for rule in matches).join ""
    if 0 < matches.length
      pattern: (rule.pattern for rule in matches).join " | " # Not used; for debugging only.
      passKeys: Utils.distinctCharacters passKeys
    else
      null

  setRules: (rules) ->
    # Callers map a rule to null to have it deleted, and rules without a pattern are useless.
    @rules = rules.filter (rule) -> rule and rule.pattern
    Settings.set("exclusionRules", @rules)

  postUpdateHook: (@rules) ->
    RegexpCache.clear()

# Register postUpdateHook for exclusionRules setting.
Settings.postUpdateHooks["exclusionRules"] = (value) ->
  Exclusions.postUpdateHook value

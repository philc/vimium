RegexpCache =
  cache: {}
  clear: (@cache = {}) ->
  get: (pattern) ->
    if pattern of @cache
      @cache[pattern]
    else
      result = null
      # We use try/catch to ensure that a broken regexp doesn't wholly cripple Vimium.
      try
        result = new RegExp("^" + pattern.replace(/\*/g, ".*") + "$")
      catch
        BgUtils.log "bad regexp in exclusion rule: #{pattern}"
        result = /^$/ # Match the empty string.
      @cache[pattern] = result
      return result

# The Exclusions class manages the exclusion rule setting.  An exclusion is an object with two attributes:
# pattern and passKeys.  The exclusion rules are an array of such objects.

Exclusions =
  # Make RegexpCache, which is required on the page popup, accessible via the Exclusions object.
  RegexpCache: RegexpCache

  rules: Settings.get "exclusionRules"

  # Merge the matching rules for URL, or null.  In the normal case, we use the configured @rules; hence, this
  # is the default.  However, when called from the page popup, we are testing what effect candidate new rules
  # would have on the current tab.  In this case, the candidate rules are provided by the caller.
  getRule: (url, rules) ->
    if !rules
      rules = @rules
    matchingRules = rules.filter((r) => r.pattern and url.search(RegexpCache.get(r.pattern)) >= 0)
    # An absolute exclusion rule (one with no passKeys) takes priority.
    for rule in matchingRules
      return rule unless rule.passKeys
    # Strip whitespace from all matching passKeys strings, and join them together.
    passKeys = matchingRules.map((r) => r.passKeys.split(/\s+/).join("")).join("")
    if matchingRules.length > 0
      passKeys: Utils.distinctCharacters passKeys
    else
      null

  isEnabledForUrl: (url) ->
    rule = Exclusions.getRule url
    isEnabledForUrl: not rule or rule.passKeys.length > 0
    passKeys: if rule then rule.passKeys else ""

  setRules: (rules) ->
    # Callers map a rule to null to have it deleted, and rules without a pattern are useless.
    @rules = rules.filter((rule) -> rule and rule.pattern)
    Settings.set "exclusionRules", @rules
    return

  postUpdateHook: (rules) ->
    # NOTE(mrmr1993): In FF, the |rules| argument will be garbage collected when the exclusions popup is
    # closed. Do NOT store it/use it asynchronously.
    @rules = Settings.get "exclusionRules"
    RegexpCache.clear()
    return

# Register postUpdateHook for exclusionRules setting.
Settings.postUpdateHooks["exclusionRules"] = Exclusions.postUpdateHook.bind Exclusions

root = exports ? window
extend root, {Exclusions}

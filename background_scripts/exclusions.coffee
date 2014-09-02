root = exports ? window

RegexpCache =
  cache: {}
  get: (pattern) ->
    if regexp = @cache[pattern]
      regexp
    else
      @cache[pattern] = new RegExp("^" + pattern.replace(/\*/g, ".*") + "$")

# The Exclusions class manages the exclusion rule setting.
# An exclusion is an object with two attributes: pattern and passKeys.
# The exclusions are an array of such objects (because the order matters).

root.Exclusions = Exclusions =

  rules: Settings.get("exclusionRules")

  # Return the first exclusion rule matching the URL, or null.
  getRule: (url) ->
    for rule in @rules
      return rule if url.match(RegexpCache.get(rule.pattern))
    return null

  setRules: (rules) ->
    @rules = rules.filter (rule) -> rule and rule.pattern
    Settings.set("exclusionRules",@rules)

  postUpdateHook: (rules) ->
    @rules = rules

  # Update an existing rule or add a new rule.
  updateOrAdd: (newRule) ->
    seen = false
    @rules.push(newRule)
    @setRules(@rules.map (rule) -> if rule.pattern == newRule.pattern then (if seen then null else seen = newRule) else rule)

  remove: (pattern) ->
    @setRules(@rules.filter((rule) -> rule.pattern != pattern))

  # DOM handling for the options page; populate the exclusionRules option.
  populateOption: (exclusionRulesElement,enableSaveButton) ->
    populate = =>
      while exclusionRulesElement.firstChild
        exclusionRulesElement.removeChild(exclusionRulesElement.firstChild)
      for rule in @rules
        exclusionRulesElement.appendChild(ExclusionRule.buildRuleElement(rule,enableSaveButton))
      exclusionRulesElement.appendChild(ExclusionRule.buildRuleElement({pattern: "", passKeys: ""},enableSaveButton))
    populate()
    return {
      saveOption: =>
        @setRules(ExclusionRule.extractRule(element) for element in exclusionRulesElement.getElementsByClassName('exclusionRow'))
        populate()
      restoreToDefault: =>
        Settings.clear("exclusionRules")
        populate()
    }

# Development and debug only.
# Enable this (temporarily) to restore legacy exclusion rules from backup.
if false and Settings.has("excludedUrlsBackup")
  Settings.clear("exclusionRules")
  Settings.set("excludedUrls",Settings.get("excludedUrlsBackup"))

if not Settings.has("exclusionRules") and Settings.has("excludedUrls")
  # Migration from the legacy exclusion rules (settings: "excludedUrls" -> "exclusionRules").

  parseLegacyRules = (lines) ->
    for line in lines.trim().split("\n").map((line) -> line.trim())
      if line.length and line.indexOf("#") != 0 and line.indexOf('"') != 0
        parse = line.split(/\s+/)
        { pattern: parse[0], passKeys: parse[1..].join("") }

  Exclusions.setRules(parseLegacyRules(Settings.get("excludedUrls")))
  # We'll keep a backup of the excludedUrls setting, just in case (and for testing).
  Settings.set("excludedUrlsBackup",Settings.get("excludedUrls")) if not Settings.has("excludedUrlsBackup")
  # TODO (smblott): Uncomment the following line.  It's commented for now so that anyone trying out this code
  # can revert to previous versions.
  # Settings.clear("excludedUrls")

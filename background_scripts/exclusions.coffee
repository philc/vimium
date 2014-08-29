root = exports ? window

# Exclusions is a list of exclusion rules.  This is an ordered list because the passKeys chosen are those
# associated with the first matching rule, so order matters.
# There may be at most one instance of this class.
class root.Exclusions

  constructor: (rules) ->
    @rules = (new ExclusionRule(rule.pattern,rule.passKeys) for rule in rules)

  # Return the first exclusion rule which this URL matches, or null.
  get: (url) ->
    for rule in @rules
      return rule if rule.matchUrl(url)
    return null

  # Update an existing rule or add a new rule.
  updateOrAdd: (rule) ->
    newPattern = rule.getPattern()
    newPassKeys = rule.getPassKeys()
    newRule = new ExclusionRule(newPattern,newPassKeys)
    updatedRule = false
    for rule, i in @rules
      if newPattern == rule.getPattern()
        return if newPassKeys == rule.getPassKeys()
        @rules[i] = newRule
        updatedRule = true
        break
    if !updatedRule
      @rules.push(newRule)
    Settings.set("exclusionRules",@rules)

  remove: (pattern) ->
    pattern = pattern.trim()
    @rules = (rule for rule in @rules when rule.pattern != pattern)
    Settings.set("exclusionRules",@rules)

  updateFromOptions: (fieldValueFromOptions) ->
    @rules = Exclusions.parseLegacyRules(fieldValueFromOptions)
    Settings.set("exclusionRules",@rules)

  # Return the flat, legacy representation of these rules.
  toString: ->
    (rule.toString() for rule in @rules).join("\n")

  # Static method.
  @parseLegacyRules: (rules) ->
    rules = (ExclusionRule.parseLegacy(line) for line in rules.trim().split("\n"))
    rule for rule in rules when rule

do ->
  # Build an Exclusions object from the list of rules stored in localStorage.
  # Always returns the same object.  So we can't have two objects which are out of sync.
  exclusions = null
  Settings.addReadHook "exclusionRules", (rules) ->
    if exclusions then exclusions else exclusions = new Exclusions(rules)

# Migration from the legacy representation of exclusion rules (as a single string of newline-separated
# rules). Migrate option: "excludedUrls" -> "exclusionRules".
# This legacy representation was used in version 1.45, and in GitHub on 27th Aug, 2014.
if not Settings.has("exclusionRules") and Settings.has("excludedUrls")
  rules = Exclusions.parseLegacyRules(Settings.get("excludedUrls"))
  Settings.set("exclusionRules",rules)
  # TODO (smblott, 27the Aug, 2014): We should clear the old setting here.  However, it's also safer just
  # to keep it around for a bit.
  # Settings.clear("excludedUrls")


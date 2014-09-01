root = exports ? window

# Exclusions is an ordered list of exclusion rules.  The passKeys chosen are those associated with the first matching rule.
# There should be at most one instance of this class.
class root.Exclusions

  constructor: (rules) ->
    @rules = (new ExclusionRule(rule.pattern,rule.passKeys) for rule in rules)

  # Return the first exclusion rule which this URL matches, or null.
  # TODO (smblott): Memoize this, thereby avoiding the scan and the Regexp comparisons each time we change tab.
  get: (url) ->
    for rule in @rules
      return rule if rule.matchUrl(url)
    return null

  # Update an existing rule or add a new rule.
  updateOrAdd: (newRule) ->
    for rule, i in @rules
      if newRule.getPattern() == rule.getPattern()
        return if newRule.getPassKeys() == rule.getPassKeys()
        @rules[i] = newRule
        Settings.set("exclusionRules",@rules)
        return
    @rules.push(newRule)
    Settings.set("exclusionRules",@rules)

  remove: (pattern) ->
    pattern = pattern.trim()
    @rules = (rule for rule in @rules when rule.pattern != pattern)
    Settings.set("exclusionRules",@rules)

  # Static method.
  @parseLegacyRules: (rules) ->
    rules = (ExclusionRule.parseLegacy(line) for line in rules.trim().split("\n"))
    rule for rule in rules when rule

  #
  # DOM handling for the options page...
  #
  addSelfToOptions: (parent,enableSaveButton) ->
    parent.appendChild(rule.buildRuleRow(enableSaveButton)) for rule in @rules
    callbacks =
      saveOption: (parent) =>
        rules = (ExclusionRule.mkRuleFromRow(element) for element in parent.getElementsByClassName('exclusionRow'))
        @rules = (rule for rule in rules when rule)
        Settings.set("exclusionRules",@rules)
      restoreToDefault: (parent) => true
        # FIXME (smblott): Not yet implemented.

do ->
  # Build an Exclusions object from the list of rules provided.
  # Always returns the same object.
  exclusions = null
  Settings.addReadHook "exclusionRules", (rules) ->
    if exclusions then exclusions else exclusions = new Exclusions(rules)

# Migration from the legacy representation of exclusion rules.
# Migrate option: "excludedUrls" -> "exclusionRules".
# The legacy representation was used in version 1.45, and in GitHub on 27th Aug, 2014.
if not Settings.has("exclusionRules") and Settings.has("excludedUrls")
  rules = Exclusions.parseLegacyRules(Settings.get("excludedUrls"))
  Settings.set("exclusionRules",rules)
  # TODO (smblott, 27the Aug, 2014): We should clear the old setting here.  However, it may be safer just
  # to keep it around for a bit.
  # Settings.clear("excludedUrls")


root = exports ? window

RegexpCache =
  cache: {}
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
    if 0 < matches.length
      pattern: (rule.pattern for rule in matches).join " | " # Not used; for debugging only.
      passKeys: Utils.distinctCharacters (rule.passKeys for rule in matches).join ""
    else
      null

  setRules: (rules) ->
    # Callers map a rule to null to have it deleted, and rules without a pattern are useless.
    @rules = rules.filter (rule) -> rule and rule.pattern
    Settings.set("exclusionRules", @rules)

  postUpdateHook: (rules) ->
    @rules = rules

# Development and debug only.
# Enable this (temporarily) to restore legacy exclusion rules from backup.
if false and Settings.has("excludedUrlsBackup")
  Settings.clear("exclusionRules")
  Settings.set("excludedUrls", Settings.get("excludedUrlsBackup"))

if not Settings.has("exclusionRules") and Settings.has("excludedUrls")
  # Migration from the legacy representation of exclusion rules.
  #
  # In Vimium 1.45 and in github/master on 27 August, 2014, exclusion rules are represented by the setting:
  #   excludedUrls: "http*://www.google.com/reader/*\nhttp*://mail.google.com/* jk"
  #
  # The new (equivalent) settings is:
  #   exclusionRules: [ { pattern: "http*://www.google.com/reader/*", passKeys: "" }, { pattern: "http*://mail.google.com/*", passKeys: "jk" } ]

  parseLegacyRules = (lines) ->
    for line in lines.trim().split("\n").map((line) -> line.trim())
      if line.length and line.indexOf("#") != 0 and line.indexOf('"') != 0
        parse = line.split(/\s+/)
        { pattern: parse[0], passKeys: parse[1..].join("") }

  Exclusions.setRules(parseLegacyRules(Settings.get("excludedUrls")))
  # We'll keep a backup of the "excludedUrls" setting, just in case.
  Settings.set("excludedUrlsBackup", Settings.get("excludedUrls")) if not Settings.has("excludedUrlsBackup")
  Settings.clear("excludedUrls")

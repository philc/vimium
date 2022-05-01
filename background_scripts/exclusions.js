const ExclusionRegexpCache = {
  cache: {},
  clear(cache) {
    this.cache = cache || {};
  },
  get(pattern) {
    if (pattern in this.cache) {
      return this.cache[pattern];
    } else {
      let result;
      // We use try/catch to ensure that a broken regexp doesn't wholly cripple Vimium.
      try {
        result = new RegExp("^" + pattern.replace(/\*/g, ".*") + "$");
      } catch (error) {
        BgUtils.log(`bad regexp in exclusion rule: ${pattern}`);
        result = /^$/; // Match the empty string.
      }
      this.cache[pattern] = result;
      return result;
    }
  }
};

// The Exclusions class manages the exclusion rule setting.  An exclusion is an object with two attributes:
// pattern and passKeys.  The exclusion rules are an array of such objects.
var Exclusions = {
  // Make RegexpCache, which is required on the page popup, accessible via the Exclusions object.
  RegexpCache: ExclusionRegexpCache,

  rules: Settings.get("exclusionRules"),

  // Merge the matching rules for URL, or null.  In the normal case, we use the configured @rules; hence, this
  // is the default.  However, when called from the page popup, we are testing what effect candidate new rules
  // would have on the current tab.  In this case, the candidate rules are provided by the caller.
  getRule(url, rules) {
    if (rules == null)
      rules = this.rules;
    const matchingRules = rules.filter(r => r.pattern && (url.search(ExclusionRegexpCache.get(r.pattern)) >= 0));
    // An absolute exclusion rule (one with no passKeys) takes priority.
    for (let rule of matchingRules)
      if (!rule.passKeys)
        return rule;
    // Strip whitespace from all matching passKeys strings, and join them together.
    const passKeys = matchingRules.map(r => r.passKeys.split(/\s+/).join("")).join("");
    // passKeys = (rule.passKeys.split(/\s+/).join "" for rule in matchingRules).join ""
    if (matchingRules.length > 0)
      return {passKeys: Utils.distinctCharacters(passKeys)};
    else
      return null;
  },

  isEnabledForUrl(url) {
    const rule = Exclusions.getRule(url);
    return {
      isEnabledForUrl: !rule || (rule.passKeys.length > 0),
      passKeys: rule ? rule.passKeys : ""
    };
  },

  setRules(rules) {
    // Callers map a rule to null to have it deleted, and rules without a pattern are useless.
    this.rules = rules.filter(rule => rule && rule.pattern);
    Settings.set("exclusionRules", this.rules);
  },

  // TODO(philc): Why does this take a `rules` argument if it's unused? Remove.
  postUpdateHook(rules) {
    // NOTE(mrmr1993): In FF, the |rules| argument will be garbage collected when the exclusions popup is
    // closed. Do NOT store it/use it asynchronously.
    this.rules = Settings.get("exclusionRules");
    ExclusionRegexpCache.clear();
  }
};

// Register postUpdateHook for exclusionRules setting.
Settings.postUpdateHooks["exclusionRules"] = Exclusions.postUpdateHook.bind(Exclusions);

window.Exclusions = Exclusions;

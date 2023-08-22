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
      } catch {
        if (!globalThis.isUnitTests) {
          console.log(`bad regexp in exclusion rule: ${pattern}`);
        }
        result = /^$/; // Match the empty string.
      }
      this.cache[pattern] = result;
      return result;
    }
  },
};

// The Exclusions class manages the exclusion rule setting. An exclusion is an object with two
// attributes: pattern and passKeys. The exclusion rules are an array of such objects.
const Exclusions = {
  // Make RegexpCache, which is required on the page popup, accessible via the Exclusions object.
  RegexpCache: ExclusionRegexpCache,

  // Merge the matching rules for URL, or null. In the normal case, we use the configured @rules;
  // hence, this is the default. However, when called from the page popup, we are testing what
  // effect candidate new rules would have on the current tab. In this case, the candidate rules are
  // provided by the caller.
  getRule(url, rules) {
    if (rules == null) {
      rules = Settings.get("exclusionRules");
    }
    const matchingRules = rules.filter((r) =>
      r.pattern && (url.search(ExclusionRegexpCache.get(r.pattern)) >= 0)
    );
    // An absolute exclusion rule (one with no passKeys) takes priority.
    for (const rule of matchingRules) {
      if (!rule.passKeys) return rule;
    }
    // Strip whitespace from all matching passKeys strings, and join them together.
    const passKeys = matchingRules.map((r) => r.passKeys.split(/\s+/).join("")).join("");
    // TODO(philc): Remove this commented out code.
    // passKeys = (rule.passKeys.split(/\s+/).join "" for rule in matchingRules).join ""
    if (matchingRules.length > 0) {
      return { passKeys: Utils.distinctCharacters(passKeys) };
    } else {
      return null;
    }
  },

  isEnabledForUrl(url) {
    const rule = Exclusions.getRule(url);
    return {
      isEnabledForUrl: !rule || (rule.passKeys.length > 0),
      passKeys: rule ? rule.passKeys : "",
    };
  },

  setRules(rules) {
    // Callers map a rule to null to have it deleted, and rules without a pattern are useless.
    const newRules = rules.filter((rule) => rule?.pattern);
    Settings.set("exclusionRules", newRules);
  },

  onSettingsUpdated() {
    // NOTE(mrmr1993): In FF, the |rules| argument will be garbage collected when the exclusions
    // popup is closed. Do NOT store it/use it asynchronously.
    ExclusionRegexpCache.clear();
  },
};

Settings.addEventListener("change", () => Exclusions.onSettingsUpdated());

globalThis.Exclusions = Exclusions;

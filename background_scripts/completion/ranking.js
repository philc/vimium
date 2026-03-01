// Utilities which help us compute a relevancy score for a given item.

// Whether the given things (usually URLs or titles) match any one of the query terms.
// This is used to prune out irrelevant suggestions before we try to rank them, and for
// calculating word relevancy. Every term must match at least one thing.
export function matches(queryTerms, ...things) {
  for (const term of queryTerms) {
    const regexp = RegexpCache.get(term);
    let matchedTerm = false;
    for (const thing of things) {
      if (!matchedTerm) {
        matchedTerm = thing.match(regexp);
      }
    }
    if (!matchedTerm) return false;
  }
  return true;
}

// Weights used for scoring matches.
const matchWeights = {
  matchAnywhere: 1,
  matchStartOfWord: 1,
  matchWholeWord: 1,
  // The following must be the sum of the three weights above; it is used for normalization.
  maximumScore: 3,
  //
  // Calibration factor for balancing word relevancy and recency.
  recencyCalibrator: 2.0 / 3.0,
};

// The current value of 2.0/3.0 has the effect of:
//   - favoring the contribution of recency when matches are not on word boundaries ( because 2.0/3.0 > (1)/3     )
//   - favoring the contribution of word relevance when matches are on whole words  ( because 2.0/3.0 < (1+1+1)/3 )

// Calculate a score for matching term against string.
// The score is in the range [0, matchWeights.maximumScore], see above.
// Returns: [ score, count ], where count is the number of matched characters in string.
function scoreTerm(term, string) {
  let score = 0;
  let count = 0;
  const nonMatching = string.split(RegexpCache.get(term));
  if (nonMatching.length > 1) {
    // Have match.
    score = matchWeights.matchAnywhere;
    count = nonMatching.reduce((p, c) => p - c.length, string.length);
    if (RegexpCache.get(term, "\\b").test(string)) {
      // Have match at start of word.
      score += matchWeights.matchStartOfWord;
      if (RegexpCache.get(term, "\\b", "\\b").test(string)) {
        // Have match of whole word.
        score += matchWeights.matchWholeWord;
      }
    }
  }
  return [score, count < string.length ? count : string.length];
}

// Returns a number between [0, 1] indicating how often the query terms appear in the url and title.
export function wordRelevancy(queryTerms, url, title) {
  let titleCount, titleScore;
  let urlScore = (titleScore = 0.0);
  let urlCount = (titleCount = 0);
  // Calculate initial scores.
  for (const term of queryTerms) {
    let [s, c] = scoreTerm(term, url);
    urlScore += s;
    urlCount += c;
    if (title) {
      [s, c] = scoreTerm(term, title);
      titleScore += s;
      titleCount += c;
    }
  }

  const maximumPossibleScore = matchWeights.maximumScore * queryTerms.length;

  // Normalize scores.
  urlScore /= maximumPossibleScore;
  urlScore *= normalizeDifference(urlCount, url.length);

  if (title) {
    titleScore /= maximumPossibleScore;
    titleScore *= normalizeDifference(titleCount, title.length);
  } else {
    titleScore = urlScore;
  }

  // Prefer matches in the title over matches in the URL.
  // In other words, don't let a poor urlScore pull down the titleScore.
  // For example, urlScore can be unreasonably poor if the URL is very long.
  if (urlScore < titleScore) {
    urlScore = titleScore;
  }

  // Return the average.
  return (urlScore + titleScore) / 2;
}

// Untested alternative to the above:
//   - Don't let a poor urlScore pull down a good titleScore, and don't let a poor titleScore pull
//     down a good urlScore.
//
// return Math.max(urlScore, titleScore)

let oneMonthAgo = 1000 * 60 * 60 * 24 * 30;

// Returns a score between [0, 1] which indicates how recent the given timestamp is. Items which
// are over a month old are counted as 0. This range is quadratic, so an item from one day ago has
// a much stronger score than an item from two days ago.
export function recencyScore(lastAccessedTime) {
  const recency = Date.now() - lastAccessedTime;
  const recencyDifference = Math.max(0, oneMonthAgo - recency) / oneMonthAgo;

  // recencyScore is between [0, 1]. It is 1 when recenyDifference is 0. This quadratic equation
  // will incresingly discount older history entries.
  let recencyScore = recencyDifference * recencyDifference * recencyDifference;

  // Calibrate recencyScore vis-a-vis word-relevancy scores.
  return recencyScore *= matchWeights.recencyCalibrator;
}

// Takes the difference of two numbers and returns a number between [0, 1] (the percentage difference).
function normalizeDifference(a, b) {
  const max = Math.max(a, b);
  return (max - Math.abs(a - b)) / max;
}

// We cache regexps because we use them frequently when comparing a query to history entries and
// bookmarks, and we don't want to create fresh objects for every comparison.
export const RegexpCache = {
  init() {
    this.initialized = true;
    this.clear();
  },

  clear() {
    this.cache = {};
  },

  // Get rexexp for `string` from cache, creating it if necessary.
  // Regexp meta-characters in `string` are escaped.
  // Regexp is wrapped in `prefix`/`suffix`, which may contain meta-characters (these are not
  // escaped).
  // With their default values, `prefix` and `suffix` have no effect.
  // Example:
  //   - string="go", prefix="\b", suffix=""
  //   - this returns regexp matching "google", but not "agog" (the "go" must occur at the start of
  //     a word)
  // TODO: `prefix` and `suffix` might be useful in richer word-relevancy scoring.
  get(string, prefix, suffix) {
    if (prefix == null) prefix = "";
    if (suffix == null) suffix = "";
    if (!this.initialized) this.init();
    let regexpString = Utils.escapeRegexSpecialCharacters(string);
    // Avoid cost of constructing new strings if prefix/suffix are empty (which is expected to be a
    // common case).
    if (prefix) regexpString = prefix + regexpString;
    if (suffix) regexpString = regexpString + suffix;
    // Smartcase: Regexp is case insensitive, unless `string` contains a capital letter (testing
    // `string`, not `regexpString`).
    return this.cache[regexpString] ||
      (this.cache[regexpString] = new RegExp(regexpString, Utils.hasUpperCase(string) ? "" : "i"));
  },
};

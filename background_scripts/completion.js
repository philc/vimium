// This file contains the definition of the completers used for the Vomnibox's suggestion UI. A
// completer will take a query (whatever the user typed into the Vomnibox) and return a list of
// Suggestions, e.g. bookmarks, domains, URLs from history.
//
// The Vomnibox frontend script makes a "filterCompleter" request to the background page, which in
// turn calls filter() on each these completers.
//
// A completer is a class which has three functions:
//  - filter(query): "query" will be whatever the user typed into the Vomnibox.
//  - refresh(): (optional) refreshes the completer's data source (e.g. refetches the list of
//    bookmarks).
//  - cancel(): (optional) cancels any pending, cancelable action.

// Set this to true to render relevancy when debugging the ranking scores.
const showRelevancy = false;

// TODO(philc): Consider moving out the "computeRelevancy" function.
class Suggestion {
  queryTerms;
  description;
  url;
  // A shortened URL (URI-decoded, protocol removed) suitable for dispaly purposes.
  shortUrl;
  title = "";
  // A computed relevancy value.
  relevancy;
  relevancyFunction;
  relevancyData;
  // When true, then this suggestion is automatically pre-selected in the vomnibar. This only affects
  // the suggestion in slot 0 in the vomnibar.
  autoSelect = false;
  // When true, we highlight matched terms in the title and URL. Otherwise we don't.
  highlightTerms = true;

  // The text to insert into the vomnibar input when this suggestion is selected.
  insertText;
  // This controls whether this suggestion is a candidate for deduplication after simplifying
  // its URL.
  deDuplicate = true;
  // The tab represented by this suggestion. Populated by TabCompleter.
  tabId;
  // Whether this is a suggestion provided by a user's custom search engine.
  isCustomSearch;
  // Whether this is meant to be the first suggestion from the user's custom search engine which
  // represents their query as typed, verbatim.
  isPrimarySuggestion = false;
  // The generated HTML string for showing this suggestion in the Vomnibar.
  html;
  searchUrl;

  constructor(options) {
    Object.seal(this);
    Object.assign(this, options);
  }

  // Returns the relevancy score.
  computeRelevancy() {
    // We assume that, once the relevancy has been set, it won't change. Completers must set
    // either @relevancy or @relevancyFunction.
    if (this.relevancy == null) {
      this.relevancy = this.relevancyFunction(this);
    }
    return this.relevancy;
  }

  generateHtml() {
    if (this.html) return this.html;
    const relevancyHtml = showRelevancy
      ? `<span class='relevancy'>${this.computeRelevancy()}</span>`
      : "";
    const insertTextClass = this.insertText ? "vomnibarInsertText" : "vomnibarNoInsertText";
    const insertTextIndicator = "&#8618;"; // A right hooked arrow.
    if (this.insertText && this.isCustomSearch) {
      this.title = this.insertText;
    }
    let faviconHtml = "";
    if (this.description === "tab" && !BgUtils.isFirefox()) {
      const faviconUrl = new URL(chrome.runtime.getURL("/_favicon/"));
      faviconUrl.searchParams.set("pageUrl", this.url);
      faviconUrl.searchParams.set("size", "16");
      faviconHtml = `<img class="vomnibarIcon" src="${faviconUrl.toString()}" />`;
    }
    if (this.isCustomSearch) {
      this.html = `\
<div class="vomnibarTopHalf">
   <span class="vomnibarSource ${insertTextClass}">${insertTextIndicator}</span><span class="vomnibarSource">${this.description}</span>
   <span class="vomnibarTitle">${this.highlightQueryTerms(Utils.escapeHtml(this.title))}</span>
   ${relevancyHtml}
 </div>\
`;
    } else {
      this.html = `\
<div class="vomnibarTopHalf">
   <span class="vomnibarSource ${insertTextClass}">${insertTextIndicator}</span><span class="vomnibarSource">${this.description}</span>
   <span class="vomnibarTitle">${this.highlightQueryTerms(Utils.escapeHtml(this.title))}</span>
 </div>
 <div class="vomnibarBottomHalf">
  <span class="vomnibarSource vomnibarNoInsertText">${insertTextIndicator}</span>${faviconHtml}<span class="vomnibarUrl">${
        this.highlightQueryTerms(Utils.escapeHtml(this.shortenUrl()))
      }</span>
  ${relevancyHtml}
</div>\
`;
    }
    return this.html;
  }

  // Use neat trick to snatch a domain (http://stackoverflow.com/a/8498668).
  getUrlRoot(url) {
    const a = document.createElement("a");
    a.href = url;
    return a.protocol + "//" + a.hostname;
  }

  getHostname(url) {
    const a = document.createElement("a");
    a.href = url;
    return a.hostname;
  }

  stripTrailingSlash(url) {
    if (url[url.length - 1] === "/") {
      url = url.substring(url, url.length - 1);
    }
    return url;
  }

  // Push the ranges within `string` which match `term` onto `ranges`.
  pushMatchingRanges(string, term, ranges) {
    let textPosition = 0;
    // Split `string` into a (flat) list of pairs:
    //   - for i=0,2,4,6,...
    //     - splits[i] is unmatched text
    //     - splits[i+1] is the following matched text (matching `term`)
    //       (except for the final element, for which there is no following matched text).
    // Example:
    //   - string = "Abacab"
    //   - term = "a"
    //   - splits = [ "", "A",    "b", "a",    "c", "a",    b" ]
    //                UM   M       UM   M       UM   M      UM      (M=Matched, UM=Unmatched)
    const splits = string.split(RegexpCache.get(term, "(", ")"));
    for (let index = 0, end = splits.length - 2; index <= end; index += 2) {
      const unmatchedText = splits[index];
      const matchedText = splits[index + 1];
      // Add the indices spanning `matchedText` to `ranges`.
      textPosition += unmatchedText.length;
      ranges.push([textPosition, textPosition + matchedText.length]);
      textPosition += matchedText.length;
    }
  }

  // Wraps each occurence of the query terms in the given string in a <span>.
  highlightQueryTerms(string) {
    if (!this.highlightTerms) return string;
    let ranges = [];
    const escapedTerms = this.queryTerms.map((term) => Utils.escapeHtml(term));
    for (const term of escapedTerms) {
      this.pushMatchingRanges(string, term, ranges);
    }

    if (ranges.length === 0) {
      return string;
    }

    ranges = this.mergeRanges(ranges.sort((a, b) => a[0] - b[0]));
    // Replace portions of the string from right to left.
    ranges = ranges.sort((a, b) => b[0] - a[0]);
    for (const [start, end] of ranges) {
      string = string.substring(0, start) +
        `<span class='vomnibarMatch'>${string.substring(start, end)}</span>` +
        string.substring(end);
    }
    return string;
  }

  // Merges the given list of ranges such that any overlapping regions are combined. E.g.
  //   mergeRanges([0, 4], [3, 6]) => [0, 6]. A range is [startIndex, endIndex].
  mergeRanges(ranges) {
    let previous = ranges.shift();
    const mergedRanges = [previous];
    ranges.forEach(function (range) {
      if (previous[1] >= range[0]) {
        previous[1] = Math.max(range[1], previous[1]);
      } else {
        mergedRanges.push(range);
        previous = range;
      }
    });
    return mergedRanges;
  }

  // Simplify a suggestion's URL (by removing those parts which aren't useful for display or
  // comparison).
  shortenUrl() {
    if (this.shortUrl != null) {
      return this.shortUrl;
    }
    // We get easier-to-read shortened URLs if we URI-decode them.
    let url = (Utils.decodeURIByParts(this.url) || this.url).toLowerCase();
    for (const [filter, replacements] of Suggestion.stripPatterns) {
      if (new RegExp(filter).test(url)) {
        for (const replace of replacements) {
          url = url.replace(replace, "");
        }
      }
    }

    this.shortUrl = url;
    return this.shortUrl;
  }

  // Boost a relevancy score by a factor (in the range (0,1.0)), while keeping the score in the
  // range [0,1]. This makes greater adjustments to scores near the middle of the range (so, very
  // poor relevancy scores remain very poor).
  static boostRelevancyScore(factor, score) {
    return score + (score < 0.5 ? score * factor : (1.0 - score) * factor);
  }
}

// Patterns to strip from URLs; of the form [ [ filter, replacements ], [ filter, replacements ], ... ]
//   - filter is a regexp string; a URL must match this regexp first.
//   - replacements (itself a list) is a list of regexp objects, each of which is removed from URLs
//     matching the filter.
//
// Note. This includes site-specific patterns for very-popular sites with URLs which don't work well
// in the vomnibar.
//
Suggestion.stripPatterns = [
  // Google search specific replacements; this replaces query parameters which are known to not be
  // helpful. There's some additional information here:
  // http://www.teknoids.net/content/google-search-parameters-2012
  [
    "^https?://www\\.google\\.(com|ca|com\\.au|co\\.uk|ie)/.*[&?]q=",
    "ei gws_rd url ved usg sa usg sig2 bih biw cd aqs ie sourceid es_sm"
      .split(/\s+/).map((param) => new RegExp(`\&${param}=[^&]+`)),
  ],

  // On Google maps, we get a new history entry for every pan and zoom event.
  ["^https?://www\\.google\\.(com|ca|com\\.au|co\\.uk|ie)/maps/place/.*/@", [new RegExp("/@.*")]],

  // General replacements; replaces leading and trailing fluff.
  [".", ["^https?://", "\\W+$"].map((re) => new RegExp(re))],
];

const folderSeparator = "/";

// If these names occur as top-level bookmark names, then they are not included in the names of
// bookmark folders.
const ignoredTopLevelBookmarks = {
  "Other Bookmarks": true,
  "Mobile Bookmarks": true,
  "Bookmarks Bar": true,
};

// this.bookmarks are loaded asynchronously when refresh() is called.
class BookmarkCompleter {
  async filter({ queryTerms }) {
    if (!this.bookmarks) await this.refresh();

    // If the folder separator character is the first character in any query term, then use the
    // bookmark's full path as its title. Otherwise, just use the its regular title.
    let results;
    const usePathAndTitle = queryTerms.reduce(
      (prev, term) => prev || term.startsWith(folderSeparator),
      false,
    );
    if (queryTerms.length > 0) {
      results = this.bookmarks.filter((bookmark) => {
        const suggestionTitle = usePathAndTitle ? bookmark.pathAndTitle : bookmark.title;
        if (bookmark.hasJavascriptPrefix == null) {
          bookmark.hasJavascriptPrefix = Utils.hasJavascriptPrefix(bookmark.url);
        }
        if (bookmark.hasJavascriptPrefix && bookmark.shortUrl == null) {
          bookmark.shortUrl = "javascript:...";
        }
        const suggestionUrl = bookmark.shortUrl != null ? bookmark.shortUrl : bookmark.url;
        return RankingUtils.matches(queryTerms, suggestionUrl, suggestionTitle);
      });
    } else {
      results = [];
    }
    const suggestions = results.map((bookmark) => {
      return new Suggestion({
        queryTerms,
        description: "bookmark",
        url: bookmark.url,
        title: usePathAndTitle ? bookmark.pathAndTitle : bookmark.title,
        relevancyFunction: this.computeRelevancy,
        shortUrl: bookmark.shortUrl,
        deDuplicate: (bookmark.shortUrl == null),
      });
    });
    return suggestions;
  }

  async refresh() {
    // In case refresh() is called multiple times before chrome.bookmarks.getTree() completes, only
    // call chrome.bookmarks.getTree() once.
    if (this.bookmarksTreePromise) {
      await this.bookmarksTreePromise;
      return;
    }

    this.bookmarksTreePromise = chrome.bookmarks.getTree();
    const bookmarksTree = await this.bookmarksTreePromise;
    this.bookmarks = this.traverseBookmarks(bookmarksTree)
      .filter((b) => b.url != null);
    this.bookmarksTreePromise = null;
  }

  // Traverses the bookmark hierarchy, and returns a flattened list of all bookmarks.
  traverseBookmarks(bookmarks) {
    const results = [];
    bookmarks.forEach((folder) => this.traverseBookmarksRecursive(folder, results));
    return results;
  }

  // Recursive helper for `traverseBookmarks`.
  traverseBookmarksRecursive(bookmark, results, parent) {
    if (parent == null) {
      parent = { pathAndTitle: "" };
    }
    if (
      bookmark.title &&
      !((parent.pathAndTitle === "") && ignoredTopLevelBookmarks[bookmark.title])
    ) {
      bookmark.pathAndTitle = parent.pathAndTitle + folderSeparator + bookmark.title;
    } else {
      bookmark.pathAndTitle = parent.pathAndTitle;
    }
    results.push(bookmark);
    if (bookmark.children) {
      bookmark.children.forEach((child) =>
        this.traverseBookmarksRecursive(child, results, bookmark)
      );
    }
  }

  computeRelevancy(suggestion) {
    return RankingUtils.wordRelevancy(
      suggestion.queryTerms,
      suggestion.shortUrl || suggestion.url,
      suggestion.title,
    );
  }
}

class HistoryCompleter {
  // - seenTabToOpenCompletionList: true if the user has typed only <Tab>, and nothing else.
  //   We interpret this to mean that they want to see all of their history in the Vomnibar, sorted
  //   by recency.
  async filter({ queryTerms, seenTabToOpenCompletionList }) {
    await HistoryCache.onLoaded();

    let results;
    if (queryTerms.length > 0) {
      results = HistoryCache.history
        .filter((entry) => RankingUtils.matches(queryTerms, entry.url, entry.title));
    } else if (seenTabToOpenCompletionList) {
      // The user has typed <Tab> to open the entire history (sorted by recency).
      results = HistoryCache.history;
    } else {
      results = [];
    }

    const suggestions = results.map((entry) => {
      return new Suggestion({
        queryTerms,
        description: "history",
        url: entry.url,
        title: entry.title,
        relevancyFunction: this.computeRelevancy,
        relevancyData: entry,
      });
    });
    return suggestions;
  }

  computeRelevancy(suggestion) {
    const historyEntry = suggestion.relevancyData;
    const recencyScore = RankingUtils.recencyScore(historyEntry.lastVisitTime);
    // If there are no query terms, then relevancy is based on recency alone.
    if (suggestion.queryTerms.length === 0) return recencyScore;
    const wordRelevancy = RankingUtils.wordRelevancy(
      suggestion.queryTerms,
      suggestion.url,
      suggestion.title,
    );
    // Average out the word score and the recency. Recency has the ability to pull the score up, but
    // not down.
    return (wordRelevancy + Math.max(recencyScore, wordRelevancy)) / 2;
  }
}

// The domain completer is designed to match a single-word query which looks like it is a domain.
// This supports the user experience where they quickly type a partial domain, hit tab -> enter, and
// expect to arrive there.
class DomainCompleter {
  // A map of domain -> { entry: <historyEntry>, referenceCount: <count> }
  // - `entry` is the most recently accessed page in the History within this domain.
  // - `referenceCount` is a count of the number of History entries within this domain.
  //    If `referenceCount` goes to zero, the domain entry can and should be deleted.
  domains;

  async filter({ queryTerms, query }) {
    const isMultiWordQuery = /\S\s/.test(query);
    if ((queryTerms.length === 0) || isMultiWordQuery) return [];
    if (!this.domains) await this.populateDomains();

    const firstTerm = queryTerms[0];
    const domains = Object.keys(this.domains || []).filter((d) => d.includes(firstTerm));
    const domainsAndScores = this.sortDomainsByRelevancy(queryTerms, domains);
    const result = new Suggestion({
      queryTerms,
      description: "domain",
      // This should be the URL or the domain, or an empty string, but not null.
      url: domainsAndScores[0]?.[0] || "",
      relevancy: 2.0,
    });
    return result.url.length > 0 ? [result] : [];
  }

  // Returns a list of domains of the form: [ [domain, relevancy], ... ]
  sortDomainsByRelevancy(queryTerms, domainCandidates) {
    const results = [];
    for (const domain of domainCandidates) {
      const recencyScore = RankingUtils.recencyScore(this.domains[domain].entry.lastVisitTime || 0);
      const wordRelevancy = RankingUtils.wordRelevancy(queryTerms, domain, null);
      const score = (wordRelevancy + Math.max(recencyScore, wordRelevancy)) / 2;
      results.push([domain, score]);
    }
    results.sort((a, b) => b[1] - a[1]);
    return results;
  }

  async populateDomains() {
    await HistoryCache.onLoaded();
    this.domains = {};
    HistoryCache.history.forEach((entry) => this.onVisited(entry));
    chrome.history.onVisited.addListener(this.onVisited.bind(this));
    chrome.history.onVisitRemoved.addListener(this.onVisitRemoved.bind(this));
  }

  onVisited(newPage) {
    const domain = this.parseDomainAndScheme(newPage.url);
    if (domain) {
      const slot = this.domains[domain] ||
        (this.domains[domain] = { entry: newPage, referenceCount: 0 });
      // We want each entry in our domains hash to point to the most recent History entry for that
      // domain.
      if (slot.entry.lastVisitTime < newPage.lastVisitTime) {
        slot.entry = newPage;
      }
      slot.referenceCount += 1;
    }
  }

  onVisitRemoved(toRemove) {
    if (toRemove.allHistory) {
      this.domains = {};
    } else {
      toRemove.urls.forEach((url) => {
        const domain = this.parseDomainAndScheme(url);
        if (domain && this.domains[domain] && ((this.domains[domain].referenceCount -= 1) === 0)) {
          return delete this.domains[domain];
        }
      });
    }
  }

  // Return something like "http://www.example.com" or false.
  parseDomainAndScheme(url) {
    return UrlUtils.hasFullUrlPrefix(url) && !UrlUtils.hasChromePrefix(url) &&
      url.split("/", 3).join("/");
  }
}

// Searches through all open tabs, matching on title and URL.
// If the query is empty, then return a list of open tabs, sorted by recency.
class TabCompleter {
  async filter({ queryTerms }) {
    await BgUtils.tabRecency.init();
    // We search all tabs, not just those in the current window.
    const tabs = await chrome.tabs.query({});
    const results = tabs.filter((tab) => RankingUtils.matches(queryTerms, tab.url, tab.title));
    const suggestions = results
      .map((tab) => {
        const suggestion = new Suggestion({
          queryTerms,
          description: "tab",
          url: tab.url,
          title: tab.title,
          tabId: tab.id,
          deDuplicate: false,
        });
        suggestion.relevancy = this.computeRelevancy(suggestion);
        return suggestion;
      })
      .sort((a, b) => b.relevancy - a.relevancy);
    // Boost relevancy with a multiplier so a relevant tab doesn't get crowded out by results from
    // competing completers. To prevent tabs from crowding out everything else in turn, penalize
    // them for being further down the results list by scaling on a hyperbola starting at 1 and
    // approaching 0 asymptotically for higher indexes. The multiplier and the curve fall-off were
    // subjectively chosen on the grounds that they seem to work pretty well.
    suggestions.forEach(function (suggestion, i) {
      suggestion.relevancy *= 8;
      suggestion.relevancy /= (i / 4) + 1;
    });
    return suggestions;
  }

  computeRelevancy(suggestion) {
    if (suggestion.queryTerms.length > 0) {
      return RankingUtils.wordRelevancy(suggestion.queryTerms, suggestion.url, suggestion.title);
    } else {
      return BgUtils.tabRecency.recencyScore(suggestion.tabId);
    }
  }
}

class SearchEngineCompleter {
  cancel() {
    CompletionSearch.cancel();
  }

  // TODO(philc): Consider moving to UserSearchEngines
  getUserSearchEngineForQuery(query) {
    const parts = query.trimStart().split(/\s+/);
    // For a keyword "w", we match "w search terms" and "w ", but not "w" on its own.
    if (parts.length <= 1) return;
    const keyword = parts[0];
    return UserSearchEngines.keywordToEngine[keyword];
  }

  refresh() {
    UserSearchEngines.set(Settings.get("searchEngines"));
  }

  async filter(request) {
    const { queryTerms } = request;

    const keyword = queryTerms[0];
    const queryTermsWithoutKeyword = queryTerms.slice(1);

    const userSearchEngine = UserSearchEngines.keywordToEngine[keyword];
    if (!userSearchEngine) return [];

    const searchUrl = userSearchEngine.url;

    const completions = await CompletionSearch.complete(searchUrl, queryTermsWithoutKeyword);

    const makeSuggestion = (query) => {
      const url = UrlUtils.createSearchUrl(query, searchUrl);
      return new Suggestion({
        queryTerms,
        description: userSearchEngine.description,
        url,
        title: query,
        searchUrl,
        highlightTerms: false,
        isCustomSearch: true,
        relevancy: null,
        relevancyFunction: this.computeRelevancy,
      });
    };

    const suggestions = completions.map((completion) => {
      const s = makeSuggestion(completion);
      s.insertText = completion;
      return s;
    });

    if (suggestions[0]) suggestions[0].relevancy = 1.0;

    // This is a suggestion which contains the user's query. It's the "search for exactly what I
    // just typed" option. It should always appear first in the list.
    const primarySuggestion = makeSuggestion(queryTermsWithoutKeyword.join(" "));
    primarySuggestion.relevancy = 2;
    primarySuggestion.isPrimarySuggestion = true;
    primarySuggestion.autoSelect = true;
    suggestions.unshift(primarySuggestion);

    return suggestions;
  }

  computeRelevancy({ queryTerms, title }) {
    // Tweaks:
    // - Calibration: we boost relevancy scores to try to achieve an appropriate balance between
    //   relevancy scores here, and those provided by other completers.
    // - Relevancy depends only on the title (which is the search terms), and not on the URL.
    return Suggestion.boostRelevancyScore(
      0.5,
      0.7 * RankingUtils.wordRelevancy(queryTerms, title, title),
    );
  }
}

SearchEngineCompleter.debug = false;

// A completer which calls filter() on many completers, aggregates the results, ranks them, and
// returns the top 10. All queries from the vomnibar come through a multi completer.
const maxResults = 10;

class MultiCompleter {
  constructor(completers) {
    this.completers = completers;
  }

  refresh() {
    for (const c of this.completers) {
      if (c.refresh) c.refresh();
    }
  }

  cancel() {
    for (const c of this.completers) {
      c.cancel?.();
    }
  }

  async filter(request) {
    const searchEngineCompleter = this.completers.find((c) => c instanceof SearchEngineCompleter);
    const query = request.query;
    const queryTerms = request.queryTerms;

    // The only UX where we support showing results when there are no query terms is via
    // Vomnibar.activateTabSelection, where we show the list of open tabs by recency.
    const isTabCompleter = this.completers.length == 1 &&
      this.completers[0] instanceof TabCompleter;
    if (queryTerms.length == 0 && !isTabCompleter) {
      return [];
    }

    const queryMatchesUserSearchEngine = searchEngineCompleter?.getUserSearchEngineForQuery(query);

    // If the user's query matches one of their custom search engines, then use only that engine to
    // provide completions for their query.
    const completers = queryMatchesUserSearchEngine
      ? [searchEngineCompleter]
      : this.completers.filter((c) => c != searchEngineCompleter);

    RegexpCache.clear();

    const promises = completers.map((c) => c.filter(request));
    let results = (await Promise.all(promises)).flat(1);
    results = this.postProcessSuggestions(request, queryTerms, results);
    return results;
  }

  // Rank them, simplify the URLs, and de-duplicate suggestions with the same simplified URL.
  postProcessSuggestions(request, queryTerms, suggestions) {
    for (const s of suggestions) {
      s.computeRelevancy(queryTerms);
    }
    suggestions.sort((a, b) => b.relevancy - a.relevancy);

    // Simplify URLs and remove duplicates (duplicate simplified URLs, that is).
    let count = 0;
    const seenUrls = {};

    const dedupedSuggestions = [];
    for (const s of suggestions) {
      const url = s.shortenUrl();
      if (s.deDuplicate && seenUrls[url]) continue;
      if (count++ === maxResults) break;
      seenUrls[url] = s;
      dedupedSuggestions.push(s);
    }

    // Give each completer the opportunity to tweak the suggestions.
    for (const completer of this.completers) {
      if (completer.postProcessSuggestions) {
        completer.postProcessSuggestions(request, dedupedSuggestions);
      }
    }

    // Generate HTML for the remaining suggestions and return them.
    for (const s of dedupedSuggestions) {
      s.generateHtml(request);
    }

    return dedupedSuggestions;
  }
}

// Utilities which help us compute a relevancy score for a given item.
const RankingUtils = {
  // Whether the given things (usually URLs or titles) match any one of the query terms.
  // This is used to prune out irrelevant suggestions before we try to rank them, and for
  // calculating word relevancy. Every term must match at least one thing.
  matches(queryTerms, ...things) {
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
  },

  // Weights used for scoring matches.
  matchWeights: {
    matchAnywhere: 1,
    matchStartOfWord: 1,
    matchWholeWord: 1,
    // The following must be the sum of the three weights above; it is used for normalization.
    maximumScore: 3,
    //
    // Calibration factor for balancing word relevancy and recency.
    recencyCalibrator: 2.0 / 3.0,
  },
  // The current value of 2.0/3.0 has the effect of:
  //   - favoring the contribution of recency when matches are not on word boundaries ( because 2.0/3.0 > (1)/3     )
  //   - favoring the contribution of word relevance when matches are on whole words  ( because 2.0/3.0 < (1+1+1)/3 )

  // Calculate a score for matching term against string.
  // The score is in the range [0, matchWeights.maximumScore], see above.
  // Returns: [ score, count ], where count is the number of matched characters in string.
  scoreTerm(term, string) {
    let score = 0;
    let count = 0;
    const nonMatching = string.split(RegexpCache.get(term));
    if (nonMatching.length > 1) {
      // Have match.
      score = RankingUtils.matchWeights.matchAnywhere;
      count = nonMatching.reduce((p, c) => p - c.length, string.length);
      if (RegexpCache.get(term, "\\b").test(string)) {
        // Have match at start of word.
        score += RankingUtils.matchWeights.matchStartOfWord;
        if (RegexpCache.get(term, "\\b", "\\b").test(string)) {
          // Have match of whole word.
          score += RankingUtils.matchWeights.matchWholeWord;
        }
      }
    }
    return [score, count < string.length ? count : string.length];
  },

  // Returns a number between [0, 1] indicating how often the query terms appear in the url and title.
  wordRelevancy(queryTerms, url, title) {
    let titleCount, titleScore;
    let urlScore = (titleScore = 0.0);
    let urlCount = (titleCount = 0);
    // Calculate initial scores.
    for (const term of queryTerms) {
      let [s, c] = RankingUtils.scoreTerm(term, url);
      urlScore += s;
      urlCount += c;
      if (title) {
        [s, c] = RankingUtils.scoreTerm(term, title);
        titleScore += s;
        titleCount += c;
      }
    }

    const maximumPossibleScore = RankingUtils.matchWeights.maximumScore * queryTerms.length;

    // Normalize scores.
    urlScore /= maximumPossibleScore;
    urlScore *= RankingUtils.normalizeDifference(urlCount, url.length);

    if (title) {
      titleScore /= maximumPossibleScore;
      titleScore *= RankingUtils.normalizeDifference(titleCount, title.length);
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
  },

  // Untested alternative to the above:
  //   - Don't let a poor urlScore pull down a good titleScore, and don't let a poor titleScore pull
  //     down a good urlScore.
  //
  // return Math.max(urlScore, titleScore)

  // Returns a score between [0, 1] which indicates how recent the given timestamp is. Items which
  // are over a month old are counted as 0. This range is quadratic, so an item from one day ago has
  // a much stronger score than an item from two days ago.
  recencyScore(lastAccessedTime) {
    if (!this.oneMonthAgo) {
      this.oneMonthAgo = 1000 * 60 * 60 * 24 * 30;
    }
    const recency = Date.now() - lastAccessedTime;
    const recencyDifference = Math.max(0, this.oneMonthAgo - recency) / this.oneMonthAgo;

    // recencyScore is between [0, 1]. It is 1 when recenyDifference is 0. This quadratic equation
    // will incresingly discount older history entries.
    let recencyScore = recencyDifference * recencyDifference * recencyDifference;

    // Calibrate recencyScore vis-a-vis word-relevancy scores.
    return recencyScore *= RankingUtils.matchWeights.recencyCalibrator;
  },

  // Takes the difference of two numbers and returns a number between [0, 1] (the percentage difference).
  normalizeDifference(a, b) {
    const max = Math.max(a, b);
    return (max - Math.abs(a - b)) / max;
  },
};

// We cache regexps because we use them frequently when comparing a query to history entries and
// bookmarks, and we don't want to create fresh objects for every comparison.
const RegexpCache = {
  init() {
    this.initialized = true;
    this.clear();
  },

  clear() {
    this.cache = {};
  },

  // Get rexexp for `string` from cache, creating it if necessary.
  // Regexp meta-characters in `string` are escaped.
  // Regexp is wrapped in `prefix`/`suffix`, which may contain meta-characters (these are not escaped).
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

// Provides cached access to Chrome's history. As the user browses to new pages, we add those pages
// to this history cache.
const HistoryCache = {
  size: 20000,
  // An array of History items returned from Chrome.
  history: null,

  reset() {
    this.history = null;
    chrome.history.onVisited.removeListener(this._onVisitedListener);
    chrome.history.onVisitRemoved.removeListener(this._onVisitRemovedListener);
  },

  async onLoaded() {
    if (this.history) return;
    await this.fetchHistory();
  },

  async fetchHistory() {
    if (this.chromeHistoryPromise) {
      await this.chromeHistoryPromise;
      return;
    }
    this.chromeHistoryPromise = chrome.history.search({
      text: "",
      maxResults: this.size,
      startTime: 0,
    });

    const history = await this.chromeHistoryPromise;

    // On Firefox, some history entries do not have titles.
    for (const entry of history) {
      if (entry.title == null) entry.title = "";
    }
    history.sort(this.compareHistoryByUrl);
    this.history = history;
    chrome.history.onVisited.addListener(this._onVisitedListener);
    chrome.history.onVisitRemoved.addListener(this._onVisitRemovedListener);
    this.chromeHistoryPromise = null;
  },

  compareHistoryByUrl(a, b) {
    if (a.url === b.url) return 0;
    if (a.url > b.url) return 1;
    return -1;
  },

  // When a page we've seen before has been visited again, be sure to replace our History item so it
  // has the correct "lastVisitTime". That's crucial for ranking Vomnibar suggestions.
  onVisited(newPage) {
    // On Firefox, some history entries do not have titles.
    if (newPage.title == null) newPage.title = "";
    const i = HistoryCache.binarySearch(newPage, this.history, this.compareHistoryByUrl);
    const pageWasFound = this.history[i]?.url == newPage.url;
    if (pageWasFound) {
      this.history[i] = newPage;
    } else {
      this.history.splice(i, 0, newPage);
    }
  },

  // When a page is removed from the chrome history, remove it from the vimium history too.
  onVisitRemoved(toRemove) {
    if (toRemove.allHistory) {
      this.history = [];
    } else {
      toRemove.urls.forEach((url) => {
        const i = HistoryCache.binarySearch({ url }, this.history, this.compareHistoryByUrl);
        if ((i < this.history.length) && (this.history[i].url === url)) {
          this.history.splice(i, 1);
        }
      });
    }
  },
};

HistoryCache._onVisitedListener = HistoryCache.onVisited.bind(HistoryCache);
HistoryCache._onVisitRemovedListener = HistoryCache.onVisitRemoved.bind(HistoryCache);

// Returns the matching index or the closest matching index if the element is not found. That means
// you must check the element at the returned index to know whether the element was actually found.
// This method is used for quickly searching through our history cache.
HistoryCache.binarySearch = function (targetElement, array, compareFunction) {
  let element, middle;
  let high = array.length - 1;
  let low = 0;

  while (low <= high) {
    middle = Math.floor((low + high) / 2);
    element = array[middle];
    const compareResult = compareFunction(element, targetElement);
    if (compareResult > 0) {
      high = middle - 1;
    } else if (compareResult < 0) {
      low = middle + 1;
    } else {
      return middle;
    }
  }
  // We didn't find the element. Return the position where it should be in this array.
  if (compareFunction(element, targetElement) < 0) {
    return middle + 1;
  } else {
    return middle;
  }
};

Object.assign(globalThis, {
  Suggestion,
  BookmarkCompleter,
  MultiCompleter,
  HistoryCompleter,
  DomainCompleter,
  TabCompleter,
  SearchEngineCompleter,
  HistoryCache,
  RankingUtils,
  RegexpCache,
});

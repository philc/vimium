// This is a wrapper class for completion engines.  It handles the case where a custom search engine includes a
// prefix query term (or terms).  For example:
//
//   https://www.google.com/search?q=javascript+%s
//
// In this case, we get better suggestions if we include the term "javascript" in queries sent to the
// completion engine.  This wrapper handles adding such prefixes to completion-engine queries and removing them
// from the resulting suggestions.
class EnginePrefixWrapper {
  constructor(searchUrl, engine) {
    this.searchUrl = searchUrl;
    this.engine = engine;
  }

  getUrl(queryTerms) {
    // This tests whether @searchUrl contains something of the form "...=abc+def+%s...", from which we extract
    // a prefix of the form "abc def ".
    if (/\=.+\+%s/.test(this.searchUrl)) {
      let terms = this.searchUrl.replace(/\+%s.*/, "");
      terms = terms.replace(/.*=/, "");
      terms = terms.replace(/\+/g, " ");

      queryTerms = [ ...terms.split(" "), ...queryTerms ];
      const prefix = `${terms} `;

      this.postprocessSuggestions = (suggestions) => {
        return suggestions
          .filter(s => s.startsWith(prefix))
          .map(s => s.slice(prefix.length));
      };
    }

    return this.engine.getUrl(queryTerms);
  }

  parse(xhr) {
    return this.postprocessSuggestions(this.engine.parse(xhr));
  }

  postprocessSuggestions(suggestions) { return suggestions; }
}

const CompletionSearch = {
  debug: false,
  inTransit: {},
  completionCache: new SimpleCache(2 * 60 * 60 * 1000, 5000), // Two hours, 5000 entries.
  engineCache:new SimpleCache(1000 * 60 * 60 * 1000), // 1000 hours.

  // The amount of time to wait for new requests before launching the current request (for example, if the user
  // is still typing).
  delay: 100,

  get(searchUrl, url, callback) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", url, true);
    xhr.timeout = 2500;
    // According to https://xhr.spec.whatwg.org/#request-error-steps,
    // readystatechange always gets called whether a request succeeds or not,
    // and the `readyState == 4` means an associated `state` is "done", which is true even if any error happens
    xhr.onreadystatechange = function() {
      if (xhr.readyState === 4)
        return callback(xhr.status === 200 ? xhr : null);
    };
    return xhr.send();
  },

  // Look up the completion engine for this searchUrl.  Because of DummyCompletionEngine, we know there will
  // always be a match.
  lookupEngine(searchUrl) {
    if (this.engineCache.has(searchUrl)) {
      return this.engineCache.get(searchUrl);
    } else {
      for (let engine of Array.from(CompletionEngines)) {
        engine = new engine();
        if (engine.match(searchUrl))
          return this.engineCache.set(searchUrl, engine);
      }
    }
  },

  // True if we have a completion engine for this search URL, false otherwise.
  haveCompletionEngine(searchUrl) {
    return !this.lookupEngine(searchUrl).dummy;
  },

  // This is the main entry point.
  //  - searchUrl is the search engine's URL, e.g. Settings.get("searchUrl"), or a custom search engine's URL.
  //    This is only used as a key for determining the relevant completion engine.
  //  - queryTerms are the query terms.
  //  - callback will be applied to a list of suggestion strings (which may be an empty list, if anything goes
  //    wrong).
  //
  // If no callback is provided, then we're to provide suggestions only if we can do so synchronously (ie.
  // from a cache).  In this case we just return the results.  Returns null if we cannot service the request
  // synchronously.
  //
  complete(searchUrl, queryTerms, callback = null) {
    let handler;
    const query = queryTerms.join(" ").toLowerCase();

    const returnResultsOnlyFromCache = (callback == null);
    if (callback == null) { callback = suggestions => suggestions; }

    // We don't complete queries which are too short: the results are usually useless.
    if (query.length < 4)
      return callback([]);

    // We don't complete regular URLs or Javascript URLs.
    if (queryTerms.length == 1 && Utils.isUrl(query))
      return callback([]);
    if (Utils.hasJavascriptPrefix(query))
      return callback([]);

    const completionCacheKey = JSON.stringify([ searchUrl, queryTerms ]);
    if (this.completionCache.has(completionCacheKey)) {
      if (this.debug)
        console.log("hit", completionCacheKey);
      return callback(this.completionCache.get(completionCacheKey));
    }

    // If the user appears to be typing a continuation of the characters of the most recent query, then we can
    // sometimes re-use the previous suggestions.
    if ((this.mostRecentQuery != null) && (this.mostRecentSuggestions != null) && (this.mostRecentSearchUrl != null)) {
      if (searchUrl === this.mostRecentSearchUrl) {
        const reusePreviousSuggestions = (() => {
          // Verify that the previous query is a prefix of the current query.
          if (!query.startsWith(this.mostRecentQuery.toLowerCase()))
            return false;
          // Verify that every previous suggestion contains the text of the new query.
          // Note: @mostRecentSuggestions may also be empty, in which case we drop though. The effect is that
          // previous queries with no suggestions suppress subsequent no-hope HTTP requests as the user
          // continues to type.
          for (let suggestion of this.mostRecentSuggestions)
            if (!suggestion.includes(query))
              return false;
          // Ok. Re-use the suggestion.
          return true;
        })();

        if (reusePreviousSuggestions) {
          if (this.debug)
            console.log("reuse previous query:", this.mostRecentQuery, this.mostRecentSuggestions.length);
          return callback(this.completionCache.set(completionCacheKey, this.mostRecentSuggestions));
        }
      }
    }

    // That's all of the caches we can try.  Bail if the caller is only requesting synchronous results.  We
    // signal that we haven't found a match by returning null.
    if (returnResultsOnlyFromCache)
      return callback(null);

    // We pause in case the user is still typing.
    Utils.setTimeout(this.delay, (handler = (this.mostRecentHandler = () => {
      if (handler !== this.mostRecentHandler)
        return;
      this.mostRecentHandler = null;

      // Elide duplicate requests. First fetch the suggestions...
      if (this.inTransit[completionCacheKey] == null) {
        this.inTransit[completionCacheKey] = new AsyncDataFetcher(callback => {
          const engine = new EnginePrefixWrapper(searchUrl, this.lookupEngine(searchUrl));
          const url = engine.getUrl(queryTerms);

          // TODO(philc): Do we need to return the result of this.get here, or can we remove this return statement?
          return this.get(searchUrl, url, (xhr = null) => {
            // Parsing the response may fail if we receive an unexpected or an unexpectedly-formatted response.
            // In all cases, we fall back to the catch clause, below.  Therefore, we "fail safe" in the case of
            // incorrect or out-of-date completion engines.
            let suggestions;
            try {
              suggestions = engine.parse(xhr)
                // Make all suggestions lower case. It looks odd when suggestions from one completion engine are
                // upper case, and those from another are lower case.
                .map(s => s.toLowerCase())
                // Filter out the query itself. It's not adding anything.
                .filter(s => s !== query);
              if (this.debug)
                console.log("GET", url);
            } catch (error) {
              suggestions = [];
              // We allow failures to be cached too, but remove them after just thirty seconds.
              Utils.setTimeout(30 * 1000, () => this.completionCache.set(completionCacheKey, null));
              if (this.debug)
                console.log("fail", url);
            }

            callback(suggestions);
            delete this.inTransit[completionCacheKey];
          });
        });
      }

      // ... then use the suggestions.
      this.inTransit[completionCacheKey].use(suggestions => {
        this.mostRecentSearchUrl = searchUrl;
        this.mostRecentQuery = query;
        this.mostRecentSuggestions = suggestions;
        // TODO(philc): Is this return necessary?
        return callback(this.completionCache.set(completionCacheKey, suggestions));
      });
    })));
  },

  // Cancel any pending (ie. blocked on @delay) queries.  Does not cancel in-flight queries.  This is called
  // whenever the user is typing.
  cancel() {
    if (this.mostRecentHandler != null) {
      this.mostRecentHandler = null;
      if (this.debug)
        console.log("cancel (user is typing)");
    }
  }
};

window.CompletionSearch = CompletionSearch;

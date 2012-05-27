/*
 * This contains the definition of the completers used for the Vomnibox's suggestion UI. A complter will take
 * a query (whatever the user typed into the Vomnibox) and return a list of matches, e.g. bookmarks, domains,
 * URLs from history.
 *
 * The Vomnibox frontend script makes a "filterCompleter" request to the background page, which in turn calls
 * filter() on each these completers.
 *
 * A completer is a class which has two functions:
 * - refresh(): refreshes the completer's data source (e.g. refetches the list of bookmarks from Chrome).
 * - filter(query, callback): "query" will be whatever the user typed into the Vomnibox. "callback" is a
 *   function which will be invoked with a list of LazyCompletionResults as its first argument.
 *
 * A completer's filter() function returns a list of LazyCompletionResults. This contains a relevancy score
 * for the result, as well as a function to build the full result (e.g. the HTML representing this result).
 *
 * The MultiCompleter collects a big list of LazyCompletionResults from many completers by calling each of
 * their filter functions in turn, sorts the results by relevancy, and then calls build() on the top N
 * results. This allows us to avoid generating HTML for all of the results we're not going to use.
 * The objects returned from build() are sent to the Vomnibox frontend script to be shown in the UI.
 */
var completion = (function() {

  // This is a development option, useful for tuning the ranking of vomnibox results.
  var showRelevancyScoreInResults = false;

  /*
   * An object which contains a relevancy score for the given completion, and a function which can be
   * invoked to build its HTML.
   * Calling build() should return an object of the form:
   *   { html: "", action: { functionName: "", args: [] } }
   * This object is eventually sent back to the Vomnibox frontend script. "action" contains the action to
   * be performed by the frontend script if this result is chosen (user selects it and hits enter).
   * "action" includes the function the frontendScript should execute (e.g. "navigateToUrl") along with any
   * arguments (like the URL).
   * "html" is the HTML representation of this result, with some characters emphasized to higlight the query.
   *
   * This is called "lazy" because it takes in a function to lazily compute a result's html. That operation
   * can be kind of expensive, so you only want to do it to the top completion results, after you've sorted
   * them by relevancy.
   */
  var LazyCompletionResult = function(relevancy, buildFunction) {
    this.relevancy = relevancy;
    this.build = buildFunction;
  }

  /*
   * A completer which takes in a list of keyword commands (like "wiki" for "search wikipedia") and will
   * decide if your query is a command, a URL that you want to visit, or a search term.
   */
  var SmartKeywordCompleter = Class.extend({
    /*
     * - commands: a list of commands of the form: { keyword: [title, url] }, e.g.:
     *   { "wiki ": ["Wikipedia (en)", "http://en.wikipedia.org/wiki/%s" ]
     */
    init: function(commands) {
      this.commands = commands || {};
      this.commandKeys = Object.keys(commands);
    },

    refresh: function() { },

      /** Returns the suggestions matching the user-defined commands */
    getCommandSuggestions: function(query, suggestions) {
      return this.commandKeys.filter(function(cmd) { return query.indexOf(cmd) == 0 }).map(function(cmd) {
        var term = query.slice(cmd.length);
        var desc = this.commands[cmd][0];
        var pattern = this.commands[cmd][1];
        var url = (typeof pattern == "function") ? pattern(term) : pattern.replace(/%s/g, term);

        // this will appear even before the URL/search suggestion
        var relevancy = -2;
        return new LazyCompletionResult(relevancy, function() {
          return {
            html:   createCompletionHtml(desc, term, null, relevancy),
            action: { functionName: "navigateToUrl", args: [utils.createFullUrl(url)] },
          }})
      }.proxy(this));
    },

    /** Checks if the input is a URL. If yes, returns a suggestion to visit it. If no, returns a suggestion
     * to start a web search. */
    getUrlOrSearchSuggestion: function(query, suggestions) {
      // trim query
      query = query.replace(/^\s+|\s+$/g, '');
      var isUrl = utils.isUrl(query);
      var relevancy = -1;
      return new LazyCompletionResult(relevancy, function() {
        return {
            html: createCompletionHtml(isUrl ? "goto" : "search", query, null, relevancy),
            action: { functionName: "navigateToUrl",
                args: isUrl ? [utils.createFullUrl(query)] : [utils.createSearchUrl(query)] }
        }});
    },

    filter: function(query, callback) {
      suggestions = this.getCommandSuggestions(query);
      suggestions.push(this.getUrlOrSearchSuggestion(query));
      callback(suggestions);
    }
  });

  /*
   * A generic asynchronous completer which is used by completers which have asynchronous data sources,
   * like history or bookmarks.
   */
  var AsyncCompleter = Class.extend({
    init: function() {
      this.id = utils.createUniqueId();
      this.reset();
      this.resultsReady = this.fallbackReadyCallback = function(results) { this.completions = results; }
    },

    reset: function() {
      fuzzyMatcher.invalidateFilterCache(this.id);
      this.completions = null;
    },

    /*
     * This creates an intermediate representation of a completion which will later be called with a specific
     * query.
     * - type: the type of item we're completing against, e.g. "bookmark", "history", "tab".
     * - item: the item itself. This should include a url and title property (Chrome's bookmark, history
     *   and tab objects include both of these).
     * - action: the action to take in the Vomnibox frontend 
     *
     * It's used to save us work -- we call this on every bookmark in your bookmarks list when we first fetch
     * them, for instance, and we don't want to do some the same work again every time a new query is
     * processed.
     *
     * TODO(philc): It would be nice if this could be removed; it's confusing.
     */
    createUnrankedCompletion: function(type, item, action) {
      var url = item.url;
      var completionString = [type, url, item.title].join(" ")
      action = action || { functionName: "navigateToUrl", args: [url] };
      var displayUrl = this.stripTrailingSlash(url);

      function createLazyCompletion(query) {
        // We want shorter URLs (i.e. top level domains) to rank more highly.
        var relevancy = url.length / fuzzyMatcher.calculateRelevancy(query, completionString);
        return new LazyCompletionResult(relevancy, function() {
          return {
            html: renderFuzzy(query, createCompletionHtml(type, displayUrl, item.title, relevancy)),
            action: action
          }});
      }

      // Add one more layer of indirection: when filtering, we only need the string to match.
      // Only after we reduced the number of possible results, we call :createLazyCompletion on them to get
      // an actual completion object.
      return {
        completionString: completionString,
        createLazyCompletion: createLazyCompletion,
      }
    },

    stripTrailingSlash: function(url) {
      if (url[url.length - 1] == "/")
        url = url.substring(url, url.length - 1);
      return url;
    },

    processResults: function(query, results) {
      results = fuzzyMatcher.filter(query, results,
          function(match) { return match.completionString }, this.id);
      return results.map(function(result) { return result.createLazyCompletion(query); });
    },

    filter: function(query, callback) {
      var handler = function(results) { callback(this.processResults(query, results)); }.proxy(this);

      // are the results ready?
      if (this.completions !== null) {
        // yes: call the callback synchronously
        handler(this.completions);
      } else {
        // no: register the handler as a callback
        this.resultsReady = function(results) {
          handler(results);
          this.resultsReady = this.fallbackReadyCallback;
          this.resultsReady(results);
        }.proxy(this);
      }
    }
  });

  var FuzzyBookmarkCompleter = Class.extend({
    init: function() { this.asyncCompleter = new AsyncCompleter(); },
    filter: function(query, callback) { return this.asyncCompleter.filter(query, callback); },

    // Traverses the bookmark hierarhcy and retuns a list of all bookmarks in the tree.
    traverseBookmarkTree: function(bookmarks) {
      var results = [];
      var toVisit = bookmarks;
      while (toVisit.length > 0) {
        var bookmark = toVisit.shift();
        results.push(bookmark);
        if (bookmark.children)
          toVisit.push.apply(toVisit, bookmark.children);
      }
      return results;
    },

    refresh: function() {
      this.asyncCompleter.reset();
      chrome.bookmarks.getTree(function(bookmarks) {
        var results = this.traverseBookmarkTree(bookmarks);
        var validResults = results.filter(function(b) { return b.url !== undefined; });
        var matches = validResults.map(function(bookmark) {
          return this.asyncCompleter.createUnrankedCompletion("bookmark", bookmark);
        }.proxy(this));
        this.asyncCompleter.resultsReady(matches);
      }.proxy(this));
    }
  });

  var FuzzyHistoryCompleter = Class.extend({
    init: function(maxResults) {
      this.asyncCompleter = new AsyncCompleter();
      this.maxResults = maxResults;
    },

    filter: function(query, callback) { return this.asyncCompleter.filter(query, callback); },

    refresh: function() {
      this.asyncCompleter.reset();

      historyCache.use(function(history) {
        this.asyncCompleter.resultsReady(history.slice(-this.maxResults).map(function(item) {
          return this.asyncCompleter.createUnrankedCompletion("history", item);
        }.proxy(this)));
      }.proxy(this));
    }
  });

  var FuzzyTabCompleter = Class.extend({
    init: function() { this.asyncCompleter = new AsyncCompleter(); },

    filter: function(query, callback) { return this.asyncCompleter.filter(query, callback); },

    refresh: function() {
      this.asyncCompleter.reset();
      chrome.tabs.getAllInWindow(null, function(tabs) {
        this.asyncCompleter.resultsReady(tabs.map(function(tab) {
          return this.asyncCompleter.createUnrankedCompletion("tab", tab,
              { functionName: "switchToTab", args: [tab.id] });
        }.proxy(this)));
      }.proxy(this));
    }
  });

  /*
   * A completer which matches only domains from sites in your history with the current query.
   */
  var DomainCompleter = Class.extend({
    // A mapping of doamin => useHttps, where useHttps is a boolean.
    domains: null,

    withDomains: function(callback) {
      var self = this;
      function buildResult() {
        return Object.keys(self.domains).map(function(dom) {
          return [dom, self.domains[dom]];
        });
      }
      if (self.domains !== null)
        return callback(buildResult());

      self.domains = {};

      function processDomain(domain, https) {
        // non-www version is preferrable, so check if we have it already
        if (domain.indexOf('www.') == 0 && self.domains.hasOwnProperty(domain.slice(4)))
          domain = domain.slice(4);

        // HTTPS is preferrable
        https = https || self.domains[domain] || self.domains['www.' + domain];

        self.domains[domain] = !!https;
        delete self.domains['www.' + domain];
      }

      function processUrl(url) {
        parts = url.split('/');
        processDomain(parts[2], parts[0] == 'https:');
      }

      historyCache.use(function(history) {
        history.forEach(function(item) { processUrl(item.url); });
      });

      chrome.history.onVisited.addListener(function(item) { processUrl(item.url); });

      callback(buildResult());
    },

    refresh: function() { },

    filter: function(query, callback) {
      var best = null;
      this.withDomains(function(domains) {
        var bestOffset = 1000;
        domains.forEach(function(result) {
          var domain = result[0];
          var protocol = result[1] ? 'https' : 'http';

          var offset = domain.indexOf(query);
          if (offset < 0 || offset >= bestOffset)
            return;

          // found a new optimum
          bestOffset = offset;
          var relevancy = -1.5;
          best = new LazyCompletionResult(relevancy, function() {
            return {
              html:   createCompletionHtml("site", domain, null, relevancy),
              action: { functionName: "navigateToUrl", args: [protocol + "://" + domain] },
            }});
        });
      });
      callback(best ? [best] : []);
    }
  });

  /*
   * A meta-completer merges and sorts the results retrieved from a list of other completers.
   */
  var MultiCompleter = Class.extend({
    // Used to hide results which are not very relevant. Increase this to include more results.
    maximiumRelevancyThreshold: 0.03,

    /*
     * - minQueryLength: the min length of a query. Anything less will return no results.
     */
    init: function(sources, minQueryLength) {
      if (minQueryLength === undefined)
        minQueryLength = 1;
      this.sources = sources;
      this.minQueryLength = minQueryLength;
    },

    refresh: function() { this.sources.forEach(function(source) { source.refresh(); }); },

    filter: function(query, maxResults, callback) {
      if (query.length < this.minQueryLength) {
        callback([]);
        return;
      }

      var allResults = [];
      var counter = this.sources.length;

      var self = this;
      this.sources.forEach(function(source) {
        source.filter(query, function(results) {
          allResults = allResults.concat(results);
          if (--counter > 0)
            return;
          allResults = allResults.filter(
              function(result) { return result.relevancy <= self.maximiumRelevancyThreshold });

          // all sources have provided results by now, so we can sort and return
          allResults.sort(function(a,b) { return a.relevancy - b.relevancy; });
          // evalulate lazy completions for the top n results
          callback(allResults.slice(0, maxResults).map(function(result) { return result.build(); }));
        });
      });
    }
  });

  /** Singleton object that provides helpers and caching for fuzzy completion. */
  var fuzzyMatcher = (function() {
    var self = {};

    self.timeToClean = 0;
    self.cacheSize = 1000;
    self.regexNonWord = /[\W_]/ig;

    // cache generated regular expressions
    self.regexpCache = {};
    // cache filtered results from recent queries
    self.filterCache = {};
    self.normalizationCache = {};

    /*
     * Normalizes the query by stripping any non-word characters and converting to lowercase.
     */
    self.normalize = function(query) {
      if (!(query in self.normalizationCache))
        self.normalizationCache[query] = query.replace(self.regexNonWord, "").toLowerCase();
      return self.normalizationCache[query];
    }

    /** Returns the non-matching and matching string parts, in alternating order (starting with a
     * non-matching part) or null, if the string doesn't match the query.
     *
     * Sample: match("codecodec","code.google.com/codec") would yield ["", "code", ".google.com/", "codec"]
     *
     * Note that this function matches the longest possible parts of a string and is therefore not very
     * efficient. There it falls back to a more performant, but less accurate regex matching if the
     * normalized query is longer than 10 characters.
     *
     * _Don't use this to check if a string matches a query_. Use `getRegexp(query).test(str)` instead.
     */
    self.getMatchGroups = function(query, str) {
      query = self.normalize(query);
      if (query.length == 0)
        return str.length ? [str] : [];
      if (query.length > 15) {
        // for long query strings, the method is much too inefficient, so fall
        // back to the less accurate regex matching
        return self.getRegexp(query).exec(str).slice(1);
      }

      for (var i = query.length; i >= 1; --i) {
        var part = query.slice(0, i);
        var partOffset = str.toLowerCase().indexOf(part);
        if (partOffset < 0)
          continue;

        // we use recursive backtracking here, this is why it's slow.
        rest = self.getMatchGroups(query.slice(i), str.slice(partOffset + i));
        if (!rest) continue;

        return [
          str.slice(0, partOffset),
          part,
        ].concat(rest);
      }
      return null;
    }

    /** Calculates a very simple similarity value between a :query and a :string */
    self.calculateRelevancy = function(query, str) {
      query = self.normalize(query);
      str   = self.normalize(str);
      var sum = 0;

      // Ignore any matches between the query and the str which are 2 characters are less.
      var minimumCharacterMatch = 3;
      // only iterate over slices of the query starting at an offset up to 20 to save resources
      for (var start = 0; start < 20 && start < query.length; ++start) {
        for (var i = query.length; i >= start + (minimumCharacterMatch - 1); --i) {
          if (str.indexOf(query.slice(start, i)) >= 0) {
            var length = i - start;
            sum += length * length;
            break;
          }
        }
      }
      return sum * sum * sum;
    }

    /** Trims the size of the caches to the configured size using a FIFO algorithm. */
    self.cleanCache = function() {
      // remove old cached regexes
      Object.keys(self.regexpCache).slice(self.cacheSize).forEach(function(query) {
        delete self.regexpCache[query];
      });
      // remove old cached normalization results
      Object.keys(self.normalizationCache).slice(self.cacheSize).forEach(function(query) {
        delete self.normalizationCache[query];
      });
    }

    /** Returns a regex that matches a string using a fuzzy :query. Example: The :query "abc" would result
     * in a regex like /^([^a])*(a)([^b])*(b)([^c])*(c)(.*)$/
     */
    self.getRegexp = function(query) {
      query = self.normalize(query);
      if (!(query in self.regexpCache)) {
        // build up a regex for fuzzy matching. This is the fastest method I checked (faster than:
        // string building, splice, concat, multi-level join)
        var regex = ['^'];
        for (var i = 0; i < query.length; ++i) {
          regex.push('([^');
          regex.push(query[i]);
          regex.push(']*)(');
          regex.push(query[i]);
          regex.push(')');
        }
        regex.push('(.*)$');
        self.regexpCache[query] = new RegExp(regex.join(''), 'i');
      }
      return self.regexpCache[query];
    }

    /** Clear the cache for the given source, e.g. for refreshing */
    self.invalidateFilterCache = function(id) {
      self.filterCache[id] = {};
    }

    /** Filters a collection :source using fuzzy matching against an input string :query. If a query with
     * a less specific query was issued before (e.g. if the user added a letter to the query), the cached
     * results of the last filtering are used as a starting point, instead of :source.
     */
    self.filter = function(query, source, getValue, id) {
      if (!(id in self.filterCache))
        self.filterCache[id] = {};

      // find the most narrow list of results in the cache
      var optSpecificity = source.length;
      var specificity;
      for (key in self.filterCache[id]) {
        if (!self.filterCache[id].hasOwnProperty(key))
          continue;

        if ((query.indexOf(key) != 0 && key.indexOf(query) != 0) || key.length > query.length) {
          // cache entry no longer needed
          delete self.filterCache[id][key];
          continue;
        }

        // is this a plausible result set to use as a source?
        if (query.indexOf(key) < 0)
          continue;

        // is this cache entry the most specific so far?
        specificity = self.filterCache[id][key].length;
        if (specificity < optSpecificity) {
          source = self.filterCache[id][key];
          optSpecificity = specificity;
        }
      }

      // don't clean up the caches every iteration
      if (++self.timeToClean > 100) {
        self.timeToClean = 0;
        self.cleanCache();
      }

      var regexp = self.getRegexp(query);
      var filtered = source.filter(function(x) { return regexp.test(getValue(x)) });
      self.filterCache[id][query] = filtered;
      return filtered;
    }

    return self;
  })();

  var htmlRegex = /<[^>]*>|&[a-z]+;/gi;

  /** Strips HTML tags and entities using a naive regex replacement. Optionally, saves the stripped
   * HTML tags in a dictionary indexed by the position where the tag should be reinserted. */
  function stripHtmlTags(str, positions) {
    if (!positions)
      return str.replace(htmlRegex, '');

    var match = str.match(htmlRegex);
    if (!match) return;
    match.reverse();
    var split = str.split(htmlRegex);
    var offset = 0;
    var i = 0;
    split.forEach(function(text) {
      if (match.length > 0)
        positions[offset += text.length] = match.pop();
    });

    return split.join('');
  }

  /*
   * Creates the HTML used to display this completion.
   * :title and :relevancy are optional.
   */
  function createCompletionHtml(type, url, title, relevancy) {
    title = title || "";
    var html = '<span class="source">' + type + '</span> ' + utils.escapeHtml(url);
    if (title.length > 0)
      html += '<span class="title">' + utils.escapeHtml(title) + '</span>';
    if (showRelevancyScoreInResults)
      html += '<span class="relevancy">' + (Math.floor(relevancy * 100000) / 100000.0) + '</span>';
    return html;
  }

  /** Renders a completion by marking fuzzy-matched parts. */
  function renderFuzzy(query, html) {
    // we want to match the content in HTML tags, but not the HTML tags themselves, so we remove the
    // tags and reinsert them after the matching process
    var htmlTags = {};
    var groups = fuzzyMatcher.getMatchGroups(query, stripHtmlTags(html, htmlTags));

    html = [];
    var htmlOffset = 0;

    // this helper function adds the HTML generated _for one single character_ to the HTML output
    // and reinserts HTML tags stripped before, if they were at this position
    function addToHtml(str) {
      if (htmlOffset in htmlTags)
        html.push(htmlTags[htmlOffset]);
      html.push(str);
      ++htmlOffset;
    }

    function addCharsWithDecoration(str, before, after) {
      before = before || '';
      after = after || '';
      for (var i = 0; i < str.length; ++i)
        addToHtml(before + str[i] + after);
    }

    // Don't render matches between the query and the str which are 2 characters are less.
    var minimumCharacterMatch = 3;

    // iterate over the match groups. They are non-matched and matched string parts, in alternating order
    for (var i = 0; i < groups.length; ++i) {
      if (i % 2 == 0 || groups[i].length < minimumCharacterMatch)
        // we have a non-matched part, it could have several characters. We need to insert them character
        // by character, so that addToHtml can keep track of the position in the original string
        addCharsWithDecoration(groups[i]);
      else
        // we have a matched part. In addition to the characters themselves, we add some decorating HTML.
        addCharsWithDecoration(groups[i], '<span class="fuzzyMatch">', '</span>');
    };

    // call it another time so that a tag at the very last position is reinserted
    addToHtml('');
    return html.join('');
  }

  /** Singleton object that provides fast access to the Chrome history */
  var historyCache = (function() {
    var size = 20000;
    var cachedHistory = null;

    function use(callback) {
      if (cachedHistory !== null)
        return callback(cachedHistory);

      chrome.history.search({ text: '', maxResults: size, startTime: 0 }, function(history) {
        // sorting in ascending order, so we can push new items to the end later
        history.sort(function(a, b) {
          return (a.lastVisitTime|| 0) - (b.lastVisitTime || 0);
        });
        cachedHistory = history;
        callback(history);
      });

      chrome.history.onVisited.addListener(function(item) {
        // only cache newly visited sites
        if (item.visitCount === 1)
          cachedHistory.push(item);
      });
    }

    return { use: use };
  })();

  // public interface
  return {
    FuzzyBookmarkCompleter: FuzzyBookmarkCompleter,
    FuzzyHistoryCompleter: FuzzyHistoryCompleter,
    FuzzyTabCompleter: FuzzyTabCompleter,
    SmartKeywordCompleter: SmartKeywordCompleter,
    DomainCompleter: DomainCompleter,
    MultiCompleter: MultiCompleter
  };
})()

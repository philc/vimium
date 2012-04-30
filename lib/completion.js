var completion = (function() {

  //============ Helper functions and objects ============//

  /** Singleton object that provides helpers and caching for fuzzy completion. */
  var fuzzyMatcher = (function() {
    var self = {};

    self.timeToClean = 0;
    self.cacheSize = 1000;
    self.regexNonWord = /[\W_]/ig;

    // cache generated regular expressions
    self.matcherCache = {};
    // cache filtered results from recent queries
    self.filterCache = {};
    self.normalizationCache = {};

    /** Normalizes the string specified in :query. Strips any non-word characters and converts
     * to lower case. */
    self.normalize = function(query) {
      if (!(query in self.normalizationCache))
        self.normalizationCache[query] = query.replace(self.regexNonWord, '').toLowerCase();
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
     * _Don't use this to check if a string matches a query_. Use `getMatcher(query).test(str)` instead.
     */
    self.getMatchGroups = function(query, str) {
      query = self.normalize(query);
      if (query.length == 0)
        return str.length ? [str] : [];
      if (query.length > 15) {
        // for long query strings, the method is much too inefficient, so fall
        // back to the less accurate regex matching
        return self.getMatcher(query).exec(str).slice(1);
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

      // only iterate over slices of the query starting at an offset up to 10 to save resources
      for (var start = 0; start < 20 && start < query.length; ++start) {
        for (var i = query.length; i >= start; --i) {
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
      Object.keys(self.matcherCache).slice(self.cacheSize).forEach(function(query) {
        delete self.matcherCache[query];
      });
      // remove old cached normalization results
      Object.keys(self.normalizationCache).slice(self.cacheSize).forEach(function(query) {
        delete self.normalizationCache[query];
      });
    }

    /** Returns a regex that matches a string using a fuzzy :query. Example: The :query "abc" would result
     * in a regex like /^([^a])*(a)([^b])*(b)([^c])*(c)(.*)$/
     */
    self.getMatcher = function(query) {
      query = self.normalize(query);
      if (!(query in self.matcherCache)) {
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
        self.matcherCache[query] = new RegExp(regex.join(''), 'i');
      }
      return self.matcherCache[query];
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

      var matcher = self.getMatcher(query);
      var filtered = source.filter(function(x) { return matcher.test(getValue(x)) });
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

  /** Creates an action that opens :url in the current tab by default or in a new tab as an alternative. */
  function createActionOpenUrl(url) {
    var open = function(newTab, selected) {
      return function() {
        chrome.extension.sendRequest({
          handler:  newTab ? "openUrlInNewTab" : "openUrlInCurrentTab",
          url:      url,
          selected: selected
        });
      }
    }

    if (url.indexOf("javascript:") == 0)
      return [ open(false), open(false), open(false) ];
    else
      return [ open(false), open(true, true), open(true, false) ];
  }

  /** Returns an action that switches to the tab with the given :id. */
  function createActionSwitchToTab(id) {
    var open = function() {
      chrome.extension.sendRequest({ handler: 'selectSpecificTab', id: id });
    }
    return [open, open, open];
  }

  /** Creates an file-internal representation of a URL match with the given paramters */
  function createCompletionHtml(type, str, title) {
    title = title || '';
    // sanitize input, it could come from a malicious web site
    title = title.length > 0 ? ' <span class="title">' + utils.escapeHtml(title) + '</span>' : '';
    return '<em>' + type + '</em> ' + utils.escapeHtml(str) + title;
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

    // iterate over the match groups. They are non-matched and matched string parts, in alternating order
    for (var i = 0; i < groups.length; ++i) {
      if (i % 2 == 0)
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

  /** A completion class that only holds a relevancy value and a function to get HTML and action
   * properties */
  var LazyCompletion = function(relevancy, builder) {
    this.relevancy = relevancy;
    this.build = builder;
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
  })()

  /** Helper class to construct fuzzy completers for asynchronous data sources like history or bookmark
   * matchers. */
  var AsyncCompletionSource = function() {
    this.id = utils.createUniqueId();
    this.reset();
    this.resultsReady = this.fallbackReadyCallback = function(results) {
      this.completions = results;
    }
  }
  AsyncCompletionSource.prototype = {
    reset: function() {
      fuzzyMatcher.invalidateFilterCache(this.id);
      this.completions = null;
    },

    /** Convenience function to remove shared code in the completers. Creates an internal representation of
     * a fuzzy completion item that is still independent of the query. The bind function will be called with
     * the actual query as an argument later. */
    createInternalMatch: function(type, item, action) {
      var url = item.url;
      var parts = [type, url, item.title];
      var str = parts.join(' ');
      action = action || {func: 'completion.createActionOpenUrl', args: [url]};

      function createLazyCompletion(query) {
        return new LazyCompletion(url.length / fuzzyMatcher.calculateRelevancy(query, str), function() {
          return {
            html:   renderFuzzy(query, createCompletionHtml.apply(null, parts)),
            action: action,
          }});
      }

      // add one more layer of indirection: For filtering, we only need the string to match.
      // Only after we reduced the number of possible results, we call :bind on them to get
      // an actual completion object
      return {
        str: parts.join(' '),
        bind: createLazyCompletion,
      }
    },

    // Default to handle results using fuzzy matching. This can be overridden by subclasses.
    processResults: function(query, results) {
      results = fuzzyMatcher.filter(query, results, function(match) { return match.str }, this.id);
      // bind the query-agnostic, lazy results to a query
      return results.map(function(result) { return result.bind(query); });
    },

    filter: function(query, callback) {
      var self = this;

      var handler = function(results) {
        callback(self.processResults(query, results));
      }

      // are the results ready?
      if (this.completions !== null) {
        // yes: call the callback synchronously
        handler(this.completions);
      } else {
        // no: register the handler as a callback
        this.resultsReady = function(results) {
          handler(results);
          self.resultsReady = self.fallbackReadyCallback;
          self.resultsReady(results);
        }
      }
    },
  }

  //========== Completer implementations ===========//

  /** A simple completer that suggests to open the input string as an URL or to trigger a web search for the
   * given term, depending on whether it thinks the input is an URL or not. */
  var SmartCompletionSource = function(commands) {
    commands = commands || {};
    var commandKeys = Object.keys(commands);

    this.refresh = function() { };

    /** Returns the suggestions matching the user-defined commands */
    this.getCommandSuggestions = function(query, suggestions) {
      return commandKeys.filter(function(cmd) { return query.indexOf(cmd) == 0 }).map(function(cmd) {
        var term = query.slice(cmd.length);
        var desc = commands[cmd][0];
        var pattern = commands[cmd][1];
        var url = typeof pattern == 'function' ? pattern(term) : pattern.replace(/%s/g, term);

        // this will appear even before the URL/search suggestion
        return new LazyCompletion(-2, function() {
          return {
            html:   createCompletionHtml(desc, term),
            action: {func: 'completion.createActionOpenUrl', args: [utils.createFullUrl(url)]},
          }})
      });
    }

    /** Checks if the input is a URL. If yes, returns a suggestion to visit it. If no, returns a suggestion
     * to start a web search. */
    this.getUrlOrSearchSuggestion = function(query, suggestions) {
      // trim query
      query = query.replace(/^\s+|\s+$/g, '');
      var isUrl = utils.isUrl(query);

      return new LazyCompletion(-1, function() {
        return {
          html: createCompletionHtml(isUrl ? 'goto' : 'search', query),
          action: {func: 'completion.createActionOpenUrl', args: isUrl ? [utils.createFullUrl(query)]
                                                                       : [utils.createSearchUrl(query)]},
        }});
    }

    this.filter = function(query, callback) {
      suggestions = this.getCommandSuggestions(query);
      suggestions.push(this.getUrlOrSearchSuggestion(query));
      callback(suggestions);
    }
  }

  /** A fuzzy bookmark completer */
  var FuzzyBookmarkCompletionSource = function() {
    AsyncCompletionSource.call(this);
  }
  utils.extend(AsyncCompletionSource, FuzzyBookmarkCompletionSource);

  FuzzyBookmarkCompletionSource.prototype.traverseTree = function(bookmarks, results) {
    var self = this;
    bookmarks.forEach(function(bookmark) {
      results.push(bookmark);
      if (bookmark.children === undefined)
        return;
      self.traverseTree(bookmark.children, results);
    });
  }

  FuzzyBookmarkCompletionSource.prototype.refresh = function() {
    var self = this; self.reset();
    chrome.bookmarks.getTree(function(bookmarks) {
      var results = [];
      self.traverseTree(bookmarks, results);

      self.resultsReady(results.filter(function(b) { return b.url !== undefined; })
                              .map(function(bookmark) {
        return self.createInternalMatch('bookmark', bookmark);
      }));
    });
  }

  /** A fuzzy history completer */
  var FuzzyHistoryCompletionSource = function(maxResults) {
    AsyncCompletionSource.call(this);
    this.maxResults = maxResults;
  }
  utils.extend(AsyncCompletionSource, FuzzyHistoryCompletionSource);

  FuzzyHistoryCompletionSource.prototype.refresh = function() {
    var self = this;
    self.reset();

    historyCache.use(function(history) {
      self.resultsReady(history.slice(-self.maxResults).map(function(item) {
        return self.createInternalMatch('history', item);
      }))
    });
  }

  /** A fuzzy tab completer */
  var FuzzyTabCompletionSource = function() {
    AsyncCompletionSource.call(this);
  }
  utils.extend(AsyncCompletionSource, FuzzyTabCompletionSource);

  FuzzyTabCompletionSource.prototype.refresh = function() {
    var self = this;
    self.reset();

    chrome.tabs.getAllInWindow(null, function(tabs) {
      self.resultsReady(tabs.map(function(tab) {
        return self.createInternalMatch('tab', tab,
                                        { func: 'completion.createActionSwitchToTab',
                                          args: [tab.id] });
      }));
    });
  }

  /** A domain completer as it is provided by Chrome's omnibox */
  var DomainCompletionSource = function() {
    this.domains = null;
  }

  DomainCompletionSource.prototype.withDomains = function(callback) {
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
      history.forEach(function(item) {
        processUrl(item.url);
      });
    });

    chrome.history.onVisited.addListener(function(item) {
      processUrl(item.url);
    });

    callback(buildResult());
  }

  DomainCompletionSource.prototype.refresh = function() { }
  DomainCompletionSource.prototype.filter = function(query, callback) {
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
        best = new LazyCompletion(-1.5, function() {
          return {
            html:   createCompletionHtml('site', domain),
            action: {func: 'completion.createActionOpenUrl', args: [protocol + '://' + domain]},
          }});
      });
    });
    callback(best ? [best] : []);
  }

  /** Get completion results from the background page */
  var BackgroundCompleter = function(name) {
    this.name = name;
    this.filterPort = chrome.extension.connect({ name: 'filterCompleter' });
  }
  BackgroundCompleter.prototype = {
    refresh: function() {
      chrome.extension.sendRequest({ handler: 'refreshCompleter', name: this.name });
    },

    filter: function(query, maxResults, callback) {
      var id = utils.createUniqueId();
      this.filterPort.onMessage.addListener(function(msg) {
        if (msg.id != id) return;
        callback(msg.results.map(function(result) {
          var action = result.action;
          result.action = eval(action.func).apply(null, action.args);
          return result;
        }));
      });
      this.filterPort.postMessage({ id: id,
                                    name: this.name,
                                    query: query,
                                    maxResults: maxResults });
    },
  }

  /** A meta-completer that delegates queries and merges and sorts the results of a collection of other
   * completer instances given in :sources. The optional argument :queryThreshold determines how long a
   * query has to be to trigger a search. */
  var MultiCompleter = function(sources, queryThreshold) {
    if (queryThreshold === undefined)
      queryThreshold = 1; // default
    this.sources = sources;
    this.queryThreshold = queryThreshold;
  }
  MultiCompleter.prototype = {
    refresh: function() {
      this.sources.forEach(function(x) { x.refresh(); });
    },

    filter: function(query, maxResults, callback) {
      if (query.length < this.queryThreshold) {
        callback([]);
        return;
      }

      var self = this;
      var all = [];
      var counter = this.sources.length;

      this.sources.forEach(function(source) {
        source.filter(query, function(results) {
          all = all.concat(results);
          if (--counter > 0)
            return;

          // all sources have provided results by now, so we can sort and return
          all.sort(function(a,b) { return a.relevancy - b.relevancy; });
          // evalulate lazy completions for the top n results
          callback(all.slice(0, maxResults).map(function(result) { return result.build(); }));
        });
      });
    }
  }

  // public interface
  return {
    FuzzyBookmarkCompletionSource: FuzzyBookmarkCompletionSource,
    FuzzyHistoryCompletionSource: FuzzyHistoryCompletionSource,
    FuzzyTabCompletionSource: FuzzyTabCompletionSource,
    SmartCompletionSource: SmartCompletionSource,
    DomainCompletionSource: DomainCompletionSource,
    MultiCompleter: MultiCompleter,
    BackgroundCompleter: BackgroundCompleter,
    createActionOpenUrl: createActionOpenUrl,
    createActionSwitchToTab: createActionSwitchToTab,
  };
})()

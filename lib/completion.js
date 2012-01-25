var completion = (function() {

  //============ Helper functions and objects ============//

  /** Singleton object that provides helpers and caching for fuzzy completion. */
  var fuzzyMatcher = (function() {
    var self = {};

    self.timeToClean = 0;
    self.matcherCacheSize = 300;
    self.regexNonWord = /[\W_]/ig;

    // cache generated regular expressions
    self.matcherCache = {};
    // cache filtered results from recent queries
    self.filterCache = {};

    /** Normalizes the string specified in :query. Strips any non-word characters and converts
     * to lower case. */
    self.normalize = function(query) {
      return query.replace(self.regexNonWord, '').toLowerCase();
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

    /** Calculates a very simple similarity value between a :query and a :string. The current
     * implementation simply returns the cumulated length of query parts that are also found
     * in the string, raised to the power of 3.
     */
    self.calculateRelevancy = function(query, str) {
      query = self.normalize(query);
      str   = self.normalize(str);
      var sum = 0;
      // only iterate over slices of the query starting at an offset up to 10 to save resources
      for (var start = 0; start < 20 && start < query.length; ++start) {
        for (var i = query.length; i >= start; --i) {
          if (str.indexOf(query.slice(start, i)) >= 0) {
            sum += (i - start) * (i - start);
            break;
          }
        }
      }
      return sum * sum * sum;
    }

    /** Trims the size of the regex cache to the configured size using a FIFO algorithm. */
    self.cleanMatcherCache = function() {
      // remove old matchers
      Object.keys(self.matcherCache).forEach(function(query) {
        delete self.matcherCache[query];
      });
    }

    /** Returns a regex that matches a string using a fuzzy :query. Example: The :query "abc" would result
     * in a regex like /^([^a])*(a)([^b])*(b)([^c])*(c)(.*)$/
     */
    self.getMatcher = function(query) {
      query = self.normalize(query);
      if (!(query in self.matcherCache)) {
        // build up a regex for fuzzy matching
        // TODO use an array and .join here
        var regex = '^';
        for (var i = 0; i < query.length; ++i)
          regex += '([^' + query[i] + ']*)(' + query[i] + ')';
        self.matcherCache[query] = new RegExp(regex + '(.*)$', 'i');
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

      // find the most specific list of results in the cache
      var maxSpecificity = 0;
      var specificity;
      for (key in self.filterCache[id]) {
        if (!self.filterCache[id].hasOwnProperty(key))
          continue;

        if ((query.indexOf(key) != 0 && key.indexOf(query) != 0) || key.length > query.length) {
          // cache entry no longer needed
          delete self.filterCache[id][key];
          continue;
        }

        // is this cache entry the most specific so far?
        specificity = self.filterCache[id][key].length;
        if (query.indexOf(key) == 0 && specificity > maxSpecificity) {
          source = self.filterCache[id][key];
          maxSpecificity = specificity;
        }
      }

      // don't clean up the cache every iteration
      if (++self.timeToClean > 20) {
        self.timeToClean = 0;
        self.cleanMatcherCache();
      }

      var matcher = self.getMatcher(query);
      var filtered = source.filter(function(x) { return matcher.test(getValue(x)) });
      self.filterCache[id][query] = filtered;
      return filtered;
    }

    return self;
  })();

  var htmlRegex = /<[^>]*>|&[a-z]+;/gi;

  /** Strips HTML tags and escape sequences using a naive regex replacement. Optionally, saves the stripped
   * HTML tags in a dictionary indexed by the position where the tag should be reinserted. */
  function stripHtmlTags(str, positions) {
    if (!positions)
      return str.replace(htmlRegex, '');

    var match = str.match(htmlRegex).reverse();
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

  /** Creates a completion that renders by marking fuzzy-matched parts. */
  function createHighlightingCompletion(query, str, action, relevancy) {
    return {
      action: action,
      relevancy: relevancy,

      render: function() {
        // we want to match the content in HTML tags, but not the HTML tags themselves, so we remove the
        // tags and reinsert them after the matching process
        var htmlTags = {};
        str = stripHtmlTags(str, htmlTags);
        var groups = fuzzyMatcher.getMatchGroups(query, str);
        var html = '';
        var htmlOffset = 0;

        // this helper function adds the HTML generated _for one single character_ to the HTML output
        // and reinserts HTML tags stripped before, if they were at this position
        function addToHtml(str) {
          if (htmlOffset in htmlTags)
            html += htmlTags[htmlOffset];
          html += str;
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

        return html;
      },
    }
  }

  /** Creates an file-internal representation of a URL match with the given paramters */
  function createCompletionHtml(type, url, title) {
    title = title || '';
    // sanitize input, it could come from a malicious web site
    title = title.length > 0 ? ' <span class="title">' + utils.escapeHtml(title) + '</span>' : '';
    return '<em>' + type + '</em> ' + utils.escapeHtml(url) + title;
  }

  /** Creates a function that returns a constant value */
  function createConstantFunction(x) {
    return function() { return x; }
  }

  /** Helper class to construct fuzzy completers for asynchronous data sources like history or bookmark
   * matchers. */
  var AsyncFuzzyUrlCompleter = function() {
    this.completions = null;
    this.id = utils.createUniqueId();
    this.readyCallback = this.fallbackReadyCallback = function(results) {
      this.completions = results;
    }
    this.extractStringFromMatch = function(match) { return stripHtmlTags(match.str); }
  }
  AsyncFuzzyUrlCompleter.prototype = {
    calculateRelevancy: function(query, match) {
      return match.url.length /
        (fuzzyMatcher.calculateRelevancy(query, this.extractStringFromMatch(match)) + 1);
    },

    createAction: function(match) {
      return createActionOpenUrl(match.url);
    },

    /** Convenience function to remove shared code in the completers. Clear the completion cache, sends
     * a message to an extension port and pipes the returned message through a callback before storing it into
     * the instance's completion cache.
     */
    fetchFromPort: function(name, query, callback) {
      this.completions = null; // reset completions

      // asynchronously fetch from a port
      var port = chrome.extension.connect({ name: name }) ;
      var self = this;
      port.onMessage.addListener(function(msg) {
        self.readyCallback(callback(msg));
      });
      port.postMessage(query);
    },

    resetCache: function() {
      fuzzyMatcher.invalidateFilterCache(this.id);
    },

    filter: function(query, callback) {
      var self = this;

      var handler = function(results) {
        var filtered = fuzzyMatcher.filter(query, results, self.extractStringFromMatch, self.id);
        callback(filtered.map(function(match) {
          return createHighlightingCompletion(
                query, match.str,
                self.createAction(match),
                self.calculateRelevancy(query, match));
        }));
      }

      // are the results ready?
      if (this.completions !== null) {
        // yes: call the callback synchronously
        handler(this.completions);
      } else {
        // no: register the handler as a callback
        this.readyCallback = function(results) {
          handler(results);
          this.readyCallback = this.fallbackReadyCallback;
          this.readyCallback(results);
        }
      }
    },
  }

  //========== Completer implementations ===========//

  /** A simple completer that suggests to open the input string as an URL or to trigger a web search for the
   * given term, depending on whether it thinks the input is an URL or not. */
  var SmartCompleter = function(commands) {
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

        return {
          render: function() { return createCompletionHtml(desc, term) },
          action: createActionOpenUrl(utils.createFullUrl(url)),
          relevancy: -2 // this will appear even before the URL/search suggestion
        };
      });
    }

    /** Checks if the input is a URL. If yes, returns a suggestion to visit it. If no, returns a suggestion
     * to start a web search. */
    this.getUrlOrSearchSuggestions = function(query, suggestions) {
      // trim query
      query = query.replace(/^\s+|\s+$/g, '');
      var isUrl = utils.isUrl(query);

      return [{
        render: function() { return createCompletionHtml(isUrl ? 'goto' : 'search', query); },
        action: createActionOpenUrl(isUrl ? utils.createFullUrl(query)
                                          : utils.createSearchUrl(query)),
        relevancy: -1, // low relevancy so this should appear at the top
      }];
    }

    this.filter = function(query, callback) {
      callback(this.getCommandSuggestions(query).concat(
               this.getUrlOrSearchSuggestions(query)));
    }
  }

  /** A fuzzy history completer */
  var FuzzyHistoryCompleter = function(maxResults) {
    AsyncFuzzyUrlCompleter.call(this);
    this.maxResults = maxResults || 1000;
  }
  utils.extend(AsyncFuzzyUrlCompleter, FuzzyHistoryCompleter);
  FuzzyHistoryCompleter.prototype.refresh = function() {
    this.resetCache();
    this.fetchFromPort('getHistory', { maxResults: this.maxResults }, function(msg) {
      return msg.history.map(function(historyItem) {
        return { str: createCompletionHtml('history', historyItem.url, historyItem.title),
                 url: historyItem.url };
      });
    });
  }

  /** A fuzzy bookmark completer */
  var FuzzyBookmarkCompleter = function() {
    AsyncFuzzyUrlCompleter.call(this);
  }
  utils.extend(AsyncFuzzyUrlCompleter, FuzzyBookmarkCompleter);
  FuzzyBookmarkCompleter.prototype.refresh = function() {
    this.resetCache();
    this.fetchFromPort('getAllBookmarks', {}, function(msg) {
      return msg.bookmarks.filter(function(bookmark) { return bookmark.url !== undefined })
                          .map(function(bookmark) {
        return { str: createCompletionHtml('bookmark', bookmark.url, bookmark.title),
                 url: bookmark.url };
      })
    });
  }

  /** A fuzzy tab completer */
  var FuzzyTabCompleter = function() {
    AsyncFuzzyUrlCompleter.call(this);
  }
  utils.extend(AsyncFuzzyUrlCompleter, FuzzyTabCompleter);
  FuzzyTabCompleter.prototype.createAction = function(match) {
    var open = function() {
      chrome.extension.sendRequest({ handler: 'selectSpecificTab', id: match.tab.id });
    }
    return [ open, open ];
  }
  FuzzyTabCompleter.prototype.refresh = function() {
    this.resetCache();
    this.fetchFromPort('getTabsInCurrentWindow', {}, function(msg) {
      return msg.tabs.map(function(tab) {
        return { str: createCompletionHtml('tab', tab.url, tab.title),
                 url: tab.url,
                 tab: tab };
      });
    });
  }

  /** A meta-completer that delegates queries and merges and sorts the results of a collection of other
   * completer instances given in :sources. The optional argument :queryThreshold determines how long a
   * query has to be to trigger a refresh. */
  var MergingCompleter = function(sources, queryThreshold) {
    if (queryThreshold === undefined)
      queryThreshold = 1; // default
    this.sources = sources;
    this.queryThreshold = queryThreshold;
  }
  MergingCompleter.prototype = {
    refresh: function() {
      this.sources.forEach(function(x) { x.refresh(); });
    },

    filter: function(query, callback) {
      if (query.length < this.queryThreshold) {
        callback([]);
        return;
      }

      var all = [];
      var counter = this.sources.length;

      this.sources.forEach(function(source) {
        source.filter(query, function(results) {
          all = all.concat(results);
          if (--counter > 0)
            return;

          // all sources have provided results by now, so we can sort and return
          all.sort(function(a,b) {
            return a.relevancy - b.relevancy;
          });
          callback(all);
        });
      });
    }
  }

  // public interface
  return {
    FuzzyHistoryCompleter: FuzzyHistoryCompleter,
    FuzzyBookmarkCompleter: FuzzyBookmarkCompleter,
    FuzzyTabCompleter: FuzzyTabCompleter,
    SmartCompleter: SmartCompleter,
    MergingCompleter: MergingCompleter,
  };
})();

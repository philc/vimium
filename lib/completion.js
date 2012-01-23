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
    self.match = function(query, str) {
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
        rest = self.match(query.slice(i), str.slice(partOffset + i));
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
      queries = Object.keys(self.matcherCache);
      for (var i = 0; i < queries.length - self.matcherCacheSize; ++i)
        delete self.matcherCache(queries[i]);
    }

    /** Returns a regex that matches a string using a fuzzy :query. Example: The :query "abc" would result
     * in a regex like /^([^a])*(a)([^b])*(b)([^c])*(c)(.*)$/
     */
    self.getMatcher = function(query) {
      query = self.normalize(query);
      if (!(query in self.matcherCache)) {
        // build up a regex for fuzzy matching
        var regex = '^';
        for (var i = 0; i < query.length; ++i)
          regex += '([^' + query[i] + ']*)(' + query[i] + ')';
        self.matcherCache[query] = new RegExp(regex + '(.*)$', 'i');
      }
      return self.matcherCache[query];
    }

    /** Filters a collection :source using fuzzy matching against an input string :query. If a query with
     * a less specific query was issued before (e.g. if the user added a letter to the query), the cached
     * results of the last filtering are used as a starting point, instead of :source.
     */
    self.filter = function(query, source, getValue, id) {
      var filtered = [];
      var source = ary;

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

  /** Strips HTML tags using a naive regex replacement. Optionally, saves the stripped HTML tags in a
   * dictionary indexed by the position where the tag should be reinserted. */
  function stripHtmlTags(str, positions) {
    var result = str.replace(/<[^>]*>/g, '');
    if (!positions)
      return result;

    // we need to get information about where the tags can be reinserted after some string processing
    var start;
    var end = -1;
    var stripped = 0;
    while (0 <= (start = str.indexOf('<', end + 1))) {
      end = str.indexOf('>', start);
      positions[start - stripped] = str.slice(start, end + 1);
      stripped += end - start + 1;
    }
    return result;
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
        var groups = fuzzyMatcher.match(query, str);
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
    // to be implemented by subclasses
    refresh: function() { },

    calculateRelevancy: function(query, match) {
      return match.url.length /
        (fuzzyMatcher.calculateRelevancy(query, this.extractStringFromMatch(match)) + 1);
    },

    createAction: function(match) {
      return createActionOpenUrl(match.url);
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

    /** Checks if the input is a special command and if yes, add according suggestions to the given array */
    this.addCommandSuggestions = function(query, suggestions) {
      // check if the input is a special command
      for (var i = 0; i < commandKeys.length; ++i) {
        var key = commandKeys[i];
        if (query.indexOf(key) != 0)
          continue;

        var term = query.slice(key.length, query.length);
        var command = commands[key];
        var desc = command[0];
        var pattern = command[1];
        var url;

        if (typeof pattern === 'function')
          url = pattern(term);
        else
          url = pattern.replace(/%s/g, term);

        suggestions.push({
          render: createConstantFunction('<em>' + desc + '</em> ' + term),
          action: createActionOpenUrl(utils.createFullUrl(url)),
        });
      }
    }

    /** Checks if the input is a URL. If yes, add the URL to the list of suggestions. If no, add a search
     * query to the list of suggestions. */
    this.addUrlOrSearchSuggestion = function(query, suggestions) {
      var url, str;

      // trim query
      query = query.replace(/^\s+|\s+$/g, '');
      if (utils.isUrl(query)) {
        url = utils.createFullUrl(query);
        str = '<em>goto</em> ' + query;
      } else {
        url = utils.createSearchUrl(query);
        str = '<em>search</em> ' + query;
      }
      suggestions.push({
        render: function() { return str; },
        action: createActionOpenUrl(url),
        // relevancy will always be the lowest one, so the suggestion is at the top
        relevancy: -1,
      });
    }

    this.filter = function(query, callback) {
      var suggestions = [];
      this.addCommandSuggestions(query, suggestions);
      this.addUrlOrSearchSuggestion(query, suggestions);
      callback(suggestions);
    };
  }

  /** A fuzzy history completer */
  var FuzzyHistoryCompleter = function(maxResults) {
    AsyncFuzzyUrlCompleter.call(this);
    this.maxResults = maxResults || 1000;
  }
  FuzzyHistoryCompleter.prototype = new AsyncFuzzyUrlCompleter;
  FuzzyHistoryCompleter.prototype.refresh = function() {
    this.completions = null; // reset completions

    // asynchronously fetch history items
    var port = chrome.extension.connect({ name: "getHistory" }) ;
    var self = this;
    port.onMessage.addListener(function(msg) {
      var results = [];

      for (var i = 0; i < msg.history.length; ++i) {
        var historyItem = msg.history[i];
        var title = '';

        if (historyItem.title.length > 0)
          title = ' <span class="title">' + historyItem.title + '</span>';

        results.push({
          str: '<em>history</em> ' + historyItem.url + title,
          url: historyItem.url,
        });
      }
      port = null;
      self.readyCallback(results);
    });
    port.postMessage({ maxResults: this.maxEntries });
  }

  /** A fuzzy bookmark completer */
  var FuzzyBookmarkCompleter = function() {
    AsyncFuzzyUrlCompleter.call(this);
  }
  FuzzyBookmarkCompleter.prototype = new AsyncFuzzyUrlCompleter;
  FuzzyBookmarkCompleter.prototype.refresh = function() {
    this.completions = null; // reset completions

    var port = chrome.extension.connect({ name: "getAllBookmarks" }) ;
    var self = this;
    port.onMessage.addListener(function(msg) {
      var results = [];

      for (var i = 0; i < msg.bookmarks.length; ++i) {
        var bookmark = msg.bookmarks[i];
        if (bookmark.url === undefined)
          continue;

        var title = '';
        if (bookmark.title.length > 0)
          title = ' <span class="title">' + bookmark.title + '</span>';

        results.push({
          str: '<em>bookmark</em> ' + bookmark.url + title,
          url: bookmark.url,
        });
      }
      port = null;
      self.readyCallback(results);
    });
    port.postMessage();
  }

  /** A fuzzy tab completer */
  var FuzzyTabCompleter = function() {
    AsyncFuzzyUrlCompleter.call(this);
  }
  FuzzyTabCompleter.prototype = new AsyncFuzzyUrlCompleter;
  FuzzyTabCompleter.prototype.createAction = function(match) {
    var open = function() {
      chrome.extension.sendRequest({ handler: 'selectSpecificTab', id: match.tab.id });
    }
    return [ open, open ];
  }
  FuzzyTabCompleter.prototype.refresh = function() {
    this.completions = null; // reset completions

    var port = chrome.extension.connect({ name: 'getTabsInCurrentWindow' }) ;
    var self = this;
    port.onMessage.addListener(function(msg) {
      var results = [];

      for (var i = 0; i < msg.tabs.length; ++i) {
        var tab = msg.tabs[i];

        var title = '';
        if (tab.title.length > 0)
          title = ' <span class="title">' + tab.title + '</span>';

        results.push({
          str: '<em>tab</em> ' + tab.url + title,
          url: tab.url,
          tab: tab,
        });
      }
      port = null;
      self.readyCallback(results);
    });
    port.postMessage();
  }

  /** A meta-completer that delegates queries and merges and sorts the results of a collection of other
   * completer instances. */
  var MergingCompleter = function(sources) {
    this.sources = sources;
  }
  MergingCompleter.prototype = {
    refresh: function() {
      for (var i = 0; i < this.sources.length; ++i)
        this.sources[i].refresh();
    },

    filter: function(query, callback) {
      var all = [];
      var counter = this.sources.length;

      for (var i = 0; i < this.sources.length; ++i) {
        this.sources[i].filter(query, function(results) {
          all = all.concat(results);
          if (--counter > 0)
            return;

          // all sources have provided results by now, so we can sort and return
          all.sort(function(a,b) {
            return a.relevancy - b.relevancy;
          });
          callback(all);
        });
      }
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

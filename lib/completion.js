var completion = (function() {

  //============ Helper functions and objects ============//

  /** Singleton object that provides helpers and caching for fuzzy completion. */
  var fuzzyMatcher = (function() {
    var self = {};

    self.matcherCacheSize = 300;
    self.regexNonWord = /\W*/g;

    // cache generated regular expressions
    self.matcherCache = {};
    // cache filtered results from recent queries
    self.filterCache = {};

    /** Normalizes the string specified in :query. Strips any non-word characters and converts
      * to lower case. */
    self.normalize = function(query) {
      return query.replace(self.regexNonWord, '').toLowerCase();
    }

    /** Calculates a very simple similarity value between a :query and a :string. The current
      * implementation simply returns the length of the longest prefix of :query that is found within :str.
      */
    self.calculateRelevancy = function(query, str) {
      query = self.normalize(query);
      str   = self.normalize(str);
      for (var i = query.length; i >= 0; --i) {
        if (str.indexOf(query.slice(0, i)) >= 0)
          return i;
      }
      return 0;
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

    /** Clears the filter cache with the given ID. */
    self.clearFilterCache = function(id) {
      if (id in self.filterCache)
        delete self.filterCache[id];
    }

    /** Filters a list :ary using fuzzy matching against an input string :query. If a query with a less
      * specific query was issued before (e.g. if the user added a letter to the query), the cached results
      * of the last filtering are used as a starting point, instead of :ary.
      */
    self.filter = function(query, ary, getValue, id, callback) {
      var filtered = [];
      var source = ary;

      if (!(id in self.filterCache))
        self.filterCache[id] = {};

      // find the most specific list of sources in the cache
      var maxSpecificity = 0;
      for (key in self.filterCache[id]) {
        if (!self.filterCache[id].hasOwnProperty(key))
          continue;

        if ((query.indexOf(key) != 0 && key.indexOf(query) != 0) || key.length > query.length) {
          // cache entry no longer needed
          delete self.filterCache[id][key];
          continue;
        }

        // is this cache entry the most specific so far?
        var specificity = self.filterCache[id][key].length;
        if (query.indexOf(key) == 0 && specificity > maxSpecificity) {
          source = self.filterCache[id][key];
          maxSpecificity = specificity;
        }
      }

      // clean up
      self.cleanMatcherCache();

      var matcher = self.getMatcher(query);
      for (var i = 0; i < source.length; ++i) {
        if (!matcher.test(getValue(source[i])))
          continue;
        filtered.push(source[i]);
        callback(source[i]);
      }
      self.filterCache[id][query] = filtered;
    }

    return self;
  })();

  /** Creates an action that opens :url in the current tab by default or in a new tab as an alternative. */
  function createActionOpenUrl(url) {
    return [
      function() { window.location = url; },
      function() { window.open(url); },
    ]
  }

  /** Creates a completion that renders by marking fuzzy-matched parts. */
  function createHighlightingCompletion(query, str, action, relevancy) {
    return {
      render: function() {
        var match = fuzzyMatcher.getMatcher(query).exec(str);
        var html = '';
        for (var i = 1; i < match.length; ++i) {
          if (i % 2 == 1)
            html += match[i];
          else
            html += '<strong>' + match[i] + '</strong>';
        };
        return html;
      },
      action: action,
      relevancy: relevancy,
    }
  }

  /** Helper class to construct fuzzy completers for asynchronous data sources like history or bookmark
   * matchers. */
  var AsyncFuzzyUrlCompleter = function() {
    this.completions = null;
    this.id = utils.createUniqueId();
    this.readyCallback = function(results) {
      this.completions = results;
    }
  }
  AsyncFuzzyUrlCompleter.prototype = {
    // to be implemented by subclasses
    refresh: function() { },

    calculateRelevancy: function(query, match) {
      return match.url.length * 10 / (fuzzyMatcher.calculateRelevancy(query, match.str)+1);
    },

    filter: function(query, callback) {
      var self = this;

      var handler = function(results) {
        var filtered = [];
        fuzzyMatcher.filter(query,
                            self.completions, function(comp) { return comp.str },
                            self.id,
                            function(match) {
          filtered.push(createHighlightingCompletion(
                query, match.str,
                createActionOpenUrl(match.url),
                self.calculateRelevancy(query, match)));
        });
        callback(filtered);
      }

      // are the results ready?
      if (this.completions !== null) {
        // yes: call the callback synchronously
        handler(this.completions);
      } else {
        // no: push our handler to the handling chain
        var oldReadyCallback = this.readyCallback;
        this.readyCallback = function(results) {
          handler(results);
          this.readyCallback = oldReadyCallback;
          oldReadyCallback(results);
        }
      }
    },
  }

  //========== Completer implementations ===========//

  /** A simple completer that suggests to open the input string as an URL or to trigger a web search for the
   * given term, depending on whether it thinks the input is an URL or not. */
  var SmartCompleter = function() {
    this.refresh = function() { };

    this.filter = function(query, callback) {
      var url;
      var str;

      if (utils.isUrl(query)) {
        url = utils.createFullUrl(query);
        str = '<em>goto</em> ' + url;
      } else {
        url = utils.createSearchUrl(query);
        str = '<em>search</em> ' + query;
      }

      // call back with exactly one suggestion
      callback([{
        render: function() { return str; },
        action: createActionOpenUrl(url),
        // relevancy will always be the lowest one, so the suggestion is at the top
        relevancy: -1,
      }]);
    };
  }

  /** A fuzzy history completer */
  var FuzzyHistoryCompleter = function(maxEntries) {
    AsyncFuzzyUrlCompleter.call(this);
    this.maxEntries = maxEntries || 1000;
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
          title = ' (' + historyItem.title + ')';

        results.push({
          str: 'history: ' + historyItem.url + title,
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

        var title = '';
        if (bookmark.title.length > 0)
          title = ' (' + bookmark.title + ')';

        results.push({
          str: 'bookmark: ' + bookmark.url + title,
          url: bookmark.url,
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
          for (var i = 0; i < all.length; ++i) {
            if (!callback(all[i]))
              // the caller doesn't want any more results
              return;
          }
        });
      }
    }
  }

  // public interface
  return {
    FuzzyHistoryCompleter: FuzzyHistoryCompleter,
    FuzzyBookmarkCompleter: FuzzyBookmarkCompleter,
    SmartCompleter: SmartCompleter,
    MergingCompleter: MergingCompleter,
  };
})();

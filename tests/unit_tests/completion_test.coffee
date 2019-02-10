require "./test_helper.js"
extend(global, require "../../lib/utils.js")
extend(global, require "../../background_scripts/bg_utils.js")
extend(global, require "../../background_scripts/completion_engines.js")
extend(global, require "../../background_scripts/completion.js")
extend global, require "./test_chrome_stubs.js"

context "bookmark completer",
  setup ->
    @bookmark3 = { title: "bookmark3", url: "bookmark3.com" }
    @bookmark2 = { title: "bookmark2", url: "bookmark2.com" }
    @bookmark1 = { title: "bookmark1", url: "bookmark1.com", children: [@bookmark2] }
    global.chrome.bookmarks =
      getTree: (callback) => callback([@bookmark1])

    @completer = new BookmarkCompleter()

  should "flatten a list of bookmarks with inorder traversal", ->
    result = @completer.traverseBookmarks([@bookmark1, @bookmark3])
    assert.arrayEqual [@bookmark1, @bookmark2, @bookmark3], result

  should "return matching bookmarks when searching", ->
    @completer.refresh()
    results = filterCompleter(@completer, ["mark2"])
    assert.arrayEqual [@bookmark2.url], results.map (suggestion) -> suggestion.url

  should "return *no* matching bookmarks when there is no match", ->
    @completer.refresh()
    results = filterCompleter(@completer, ["does-not-match"])
    assert.arrayEqual [], results.map (suggestion) -> suggestion.url

  should "construct bookmark paths correctly", ->
    @completer.refresh()
    results = filterCompleter(@completer, ["mark2"])
    assert.equal "/bookmark1/bookmark2", @bookmark2.pathAndTitle

  should "return matching bookmark *titles* when searching *without* the folder separator character", ->
    @completer.refresh()
    results = filterCompleter(@completer, ["mark2"])
    assert.arrayEqual ["bookmark2"], results.map (suggestion) -> suggestion.title

  should "return matching bookmark *paths* when searching with the folder separator character", ->
    @completer.refresh()
    results = filterCompleter(@completer, ["/bookmark1", "mark2"])
    assert.arrayEqual ["/bookmark1/bookmark2"], results.map (suggestion) -> suggestion.title

context "HistoryCache",
  context "binary search",
    setup ->
      @compare = (a, b) -> a - b

    should "find elements to the left of the middle", ->
      assert.equal 0, HistoryCache.binarySearch(3, [3, 5, 8], @compare)

    should "find elements to the right of the middle", ->
      assert.equal 2, HistoryCache.binarySearch(8, [3, 5, 8], @compare)

    context "unfound elements",
      should "return 0 if it should be the head of the list", ->
        assert.equal 0, HistoryCache.binarySearch(1, [3, 5, 8], @compare)

      should "return length - 1 if it should be at the end of the list", ->
        assert.equal 0, HistoryCache.binarySearch(3, [3, 5, 8], @compare)

      should "return one passed end of array (so: array.length) if greater than last element in array", ->
        assert.equal 3, HistoryCache.binarySearch(10, [3, 5, 8], @compare)

      should "found return the position if it's between two elements", ->
        assert.equal 1, HistoryCache.binarySearch(4, [3, 5, 8], @compare)
        assert.equal 2, HistoryCache.binarySearch(7, [3, 5, 8], @compare)

  context "fetchHistory",
    setup ->
      @history1 = { url: "b.com", lastVisitTime: 5 }
      @history2 = { url: "a.com", lastVisitTime: 10 }
      history = [@history1, @history2]
      @onVisitedListener = null
      @onVisitRemovedListener = null
      global.chrome.history =
        search: (options, callback) -> callback(history)
        onVisited: { addListener: (@onVisitedListener) => }
        onVisitRemoved: { addListener: (@onVisitRemovedListener) => }
      HistoryCache.reset()

    should "store visits sorted by url ascending", ->
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history2, @history1], @results

    should "add new visits to the history", ->
      HistoryCache.use () ->
      newSite = { url: "ab.com" }
      @onVisitedListener(newSite)
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history2, newSite, @history1], @results

    should "replace new visits in the history", ->
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history2, @history1], @results
      newSite = { url: "a.com", lastVisitTime: 15 }
      @onVisitedListener(newSite)
      HistoryCache.use (@results) =>
      assert.arrayEqual [newSite, @history1], @results

    should "(not) remove page from the history, when page is not in history (it should be a no-op)", ->
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history2, @history1], @results
      toRemove = { urls: [ "x.com" ], allHistory: false }
      @onVisitRemovedListener(toRemove)
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history2, @history1], @results

    should "remove pages from the history", ->
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history2, @history1], @results
      toRemove = { urls: [ "a.com" ], allHistory: false }
      @onVisitRemovedListener(toRemove)
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history1], @results

    should "remove all pages from the history", ->
      HistoryCache.use (@results) =>
      assert.arrayEqual [@history2, @history1], @results
      toRemove = { allHistory: true }
      @onVisitRemovedListener(toRemove)
      HistoryCache.use (@results) =>
      assert.arrayEqual [], @results

context "history completer",
  setup ->
    @history1 = { title: "history1", url: "history1.com", lastVisitTime: hours(1) }
    @history2 = { title: "history2", url: "history2.com", lastVisitTime: hours(5) }

    global.chrome.history =
      search: (options, callback) => callback([@history1, @history2])
      onVisited: { addListener: -> }
      onVisitRemoved: { addListener: -> }

    @completer = new HistoryCompleter()

  should "return matching history entries when searching", ->
    assert.arrayEqual [@history1.url], filterCompleter(@completer, ["story1"]).map (entry) -> entry.url

  should "rank recent results higher than nonrecent results", ->
    stub(Date, "now", returns(hours(24)))
    results = filterCompleter(@completer, ["hist"])
    results.forEach (result) -> result.computeRelevancy()
    results.sort (a, b) -> b.relevancy - a.relevancy
    assert.arrayEqual [@history2.url, @history1.url], results.map (result) -> result.url

context "domain completer",
  setup ->
    @history1 = { title: "history1", url: "http://history1.com", lastVisitTime: hours(1) }
    @history2 = { title: "history2", url: "http://history2.com", lastVisitTime: hours(1) }
    @undef    = { title: "history2", url: "http://undefined.net", lastVisitTime: hours(1) }

    stub(HistoryCache, "use", (onComplete) => onComplete([@history1, @history2, @undef]))
    global.chrome.history =
      onVisited: { addListener: -> }
      onVisitRemoved: { addListener: -> }
    stub(Date, "now", returns(hours(24)))

    @completer = new DomainCompleter()

  should "return only a single matching domain", ->
    results = filterCompleter(@completer, ["story"])
    assert.arrayEqual ["http://history1.com"], results.map (result) -> result.url

  should "pick domains which are more recent", ->
    # These domains are the same except for their last visited time.
    assert.equal "http://history1.com", filterCompleter(@completer, ["story"])[0].url
    @history2.lastVisitTime = hours(3)
    assert.equal "http://history2.com", filterCompleter(@completer, ["story"])[0].url

  should "returns no results when there's more than one query term, because clearly it's not a domain", ->
    assert.arrayEqual [], filterCompleter(@completer, ["his", "tory"])

  should "not return any results for empty queries", ->
    assert.arrayEqual [], filterCompleter(@completer, [])

context "domain completer (removing entries)",
  setup ->
    @history1 = { title: "history1", url: "http://history1.com", lastVisitTime: hours(2) }
    @history2 = { title: "history2", url: "http://history2.com", lastVisitTime: hours(1) }
    @history3 = { title: "history2something", url: "http://history2.com/something", lastVisitTime: hours(0) }

    stub(HistoryCache, "use", (onComplete) => onComplete([@history1, @history2, @history3]))
    @onVisitedListener = null
    @onVisitRemovedListener = null
    global.chrome.history =
      onVisited: { addListener: (@onVisitedListener) => }
      onVisitRemoved: { addListener: (@onVisitRemovedListener) => }
    stub(Date, "now", returns(hours(24)))

    @completer = new DomainCompleter()
    # Force installation of listeners.
    filterCompleter(@completer, ["story"])

  should "remove 1 entry for domain with reference count of 1", ->
    @onVisitRemovedListener { allHistory: false, urls: [@history1.url] }
    assert.equal "http://history2.com", filterCompleter(@completer, ["story"])[0].url
    assert.equal 0, filterCompleter(@completer, ["story1"]).length

  should "remove 2 entries for domain with reference count of 2", ->
    @onVisitRemovedListener { allHistory: false, urls: [@history2.url] }
    assert.equal "http://history2.com", filterCompleter(@completer, ["story2"])[0].url
    @onVisitRemovedListener { allHistory: false, urls: [@history3.url] }
    assert.equal 0, filterCompleter(@completer, ["story2"]).length
    assert.equal "http://history1.com", filterCompleter(@completer, ["story"])[0].url

  should "remove 3 (all) matching domain entries", ->
    @onVisitRemovedListener { allHistory: false, urls: [@history2.url] }
    @onVisitRemovedListener { allHistory: false, urls: [@history1.url] }
    @onVisitRemovedListener { allHistory: false, urls: [@history3.url] }
    assert.equal 0, filterCompleter(@completer, ["story"]).length

  should "remove 3 (all) matching domain entries, and do it all at once", ->
    @onVisitRemovedListener { allHistory: false, urls: [ @history2.url, @history1.url, @history3.url ] }
    assert.equal 0, filterCompleter(@completer, ["story"]).length

  should "remove *all* domain entries", ->
    @onVisitRemovedListener { allHistory: true }
    assert.equal 0, filterCompleter(@completer, ["story"]).length

context "tab completer",
  setup ->
    @tabs = [
      { url: "tab1.com", title: "tab1", id: 1 }
      { url: "tab2.com", title: "tab2", id: 2 }]
    chrome.tabs = { query: (args, onComplete) => onComplete(@tabs) }
    @completer = new TabCompleter()

  should "return matching tabs", ->
    results = filterCompleter(@completer, ["tab2"])
    assert.arrayEqual ["tab2.com"], results.map (tab) -> tab.url
    assert.arrayEqual [2], results.map (tab) -> tab.tabId

context "suggestions",
  should "escape html in page titles", ->
    suggestion = new Suggestion
      queryTerms: ["queryterm"]
      type: "tab"
      url: "url"
      title: "title <span>"
      relevancyFunction: returns 1
    assert.isTrue suggestion.generateHtml({}).indexOf("title &lt;span&gt;") >= 0

  should "highlight query words", ->
    suggestion = new Suggestion
      queryTerms: ["ninj", "words"]
      type: "tab"
      url: "url"
      title: "ninjawords"
      relevancyFunction: returns 1
    expected = "<span class='vomnibarMatch'>ninj</span>a<span class='vomnibarMatch'>words</span>"
    assert.isTrue suggestion.generateHtml({}).indexOf(expected) >= 0

  should "highlight query words correctly when whey they overlap", ->
    suggestion = new Suggestion
      queryTerms: ["ninj", "jaword"]
      type: "tab"
      url: "url"
      title: "ninjawords"
      relevancyFunction: returns 1
    expected = "<span class='vomnibarMatch'>ninjaword</span>s"
    assert.isTrue suggestion.generateHtml({}).indexOf(expected) >= 0

  should "shorten urls", ->
    suggestion = new Suggestion
      queryTerms: ["queryterm"]
      type: "history"
      url: "http://ninjawords.com"
      title: "ninjawords"
      relevancyFunction: returns 1
    assert.equal -1, suggestion.generateHtml({}).indexOf("http://ninjawords.com")

context "RankingUtils.wordRelevancy",
  should "score higher in shorter URLs", ->
    highScore = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/short",  "a-title")
    lowScore  = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/longer", "a-title")
    assert.isTrue highScore > lowScore

  should "score higher in shorter titles", ->
    highScore = RankingUtils.wordRelevancy(["coffee"], "a-url", "Coffeescript")
    lowScore  = RankingUtils.wordRelevancy(["coffee"], "a-url", "Coffeescript rocks")
    assert.isTrue highScore > lowScore

  should "score higher for matching the start of a word (in a URL)", ->
    lowScore  = RankingUtils.wordRelevancy(["stack"], "http://Xstackoverflow.com/same", "a-title")
    highScore = RankingUtils.wordRelevancy(["stack"], "http://stackoverflowX.com/same", "a-title")
    assert.isTrue highScore > lowScore

  should "score higher for matching the start of a word (in a title)", ->
    lowScore  = RankingUtils.wordRelevancy(["te"], "a-url", "Dist racted")
    highScore = RankingUtils.wordRelevancy(["te"], "a-url", "Distrac ted")
    assert.isTrue highScore > lowScore

  should "score higher for matching a whole word (in a URL)", ->
    lowScore  = RankingUtils.wordRelevancy(["com"], "http://stackoverflow.comX/same", "a-title")
    highScore = RankingUtils.wordRelevancy(["com"], "http://stackoverflowX.com/same", "a-title")
    assert.isTrue highScore > lowScore

  should "score higher for matching a whole word (in a title)", ->
    lowScore  = RankingUtils.wordRelevancy(["com"], "a-url", "abc comX")
    highScore = RankingUtils.wordRelevancy(["com"], "a-url", "abcX com")
    assert.isTrue highScore > lowScore

  # # TODO: (smblott)
  # #       Word relevancy should take into account the number of matches (it doesn't currently).
  # should "score higher for multiple matches (in a URL)", ->
  #   lowScore  = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/Xxxxxx", "a-title")
  #   highScore = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/Xstack", "a-title")
  #   assert.isTrue highScore > lowScore

  # should "score higher for multiple matches (in a title)", ->
  #   lowScore  = RankingUtils.wordRelevancy(["bbc"], "http://stackoverflow.com/same", "BBC Radio 4 (XBCr4)")
  #   highScore = RankingUtils.wordRelevancy(["bbc"], "http://stackoverflow.com/same", "BBC Radio 4 (BBCr4)")
  #   assert.isTrue highScore > lowScore

context "Suggestion.pushMatchingRanges",
  should "extract ranges matching term (simple case, two matches)", ->
    ranges = []
    [ one, two, three ] = [ "one", "two", "three" ]
    suggestion = new Suggestion([], "", "", "", returns(1))
    suggestion.pushMatchingRanges("#{one}#{two}#{three}#{two}#{one}", two, ranges)
    assert.equal 2, Utils.zip([ ranges, [ [3,6], [11,14] ] ]).filter((pair) -> pair[0][0] == pair[1][0] and pair[0][1] == pair[1][1]).length

  should "extract ranges matching term (two matches, one at start of string)", ->
    ranges = []
    [ one, two, three ] = [ "one", "two", "three" ]
    suggestion = new Suggestion([], "", "", "", returns(1))
    suggestion.pushMatchingRanges("#{two}#{three}#{two}#{one}", two, ranges)
    assert.equal 2, Utils.zip([ ranges, [ [0,3], [8,11] ] ]).filter((pair) -> pair[0][0] == pair[1][0] and pair[0][1] == pair[1][1]).length

  should "extract ranges matching term (two matches, one at end of string)", ->
    ranges = []
    [ one, two, three ] = [ "one", "two", "three" ]
    suggestion = new Suggestion([], "", "", "", returns(1))
    suggestion.pushMatchingRanges("#{one}#{two}#{three}#{two}", two, ranges)
    assert.equal 2, Utils.zip([ ranges, [ [3,6], [11,14] ] ]).filter((pair) -> pair[0][0] == pair[1][0] and pair[0][1] == pair[1][1]).length

  should "extract ranges matching term (no matches)", ->
    ranges = []
    [ one, two, three ] = [ "one", "two", "three" ]
    suggestion = new Suggestion([], "", "", "", returns(1))
    suggestion.pushMatchingRanges("#{one}#{two}#{three}#{two}#{one}", "does-not-match", ranges)
    assert.equal 0, ranges.length

context "RankingUtils",
  should "do a case insensitive match", ->
    assert.isTrue RankingUtils.matches(["ari"], "maRio")

  should "do a case insensitive match on full term", ->
    assert.isTrue RankingUtils.matches(["mario"], "MARio")

  should "do a case insensitive match on several terms", ->
    assert.isTrue RankingUtils.matches(["ari"], "DOES_NOT_MATCH", "DOES_NOT_MATCH_EITHER", "MARio")

  should "do a smartcase match (positive)", ->
    assert.isTrue RankingUtils.matches(["Mar"], "Mario")

  should "do a smartcase match (negative)", ->
    assert.isFalse RankingUtils.matches(["Mar"], "mario")

  should "do a match with regexp meta-characters (positive)", ->
    assert.isTrue RankingUtils.matches(["ma.io"], "ma.io")

  should "do a match with regexp meta-characters (negative)", ->
    assert.isFalse RankingUtils.matches(["ma.io"], "mario")

  should "do a smartcase match on full term", ->
    assert.isTrue RankingUtils.matches(["Mario"], "Mario")
    assert.isFalse RankingUtils.matches(["Mario"], "mario")

  should "do case insensitive word relevancy (matching)", ->
    assert.isTrue RankingUtils.wordRelevancy(["ari"], "MARIO", "MARio") > 0.0

  should "do case insensitive word relevancy (not matching)", ->
    assert.isTrue RankingUtils.wordRelevancy(["DOES_NOT_MATCH"], "MARIO", "MARio") == 0.0

  should "every query term must match at least one thing (matching)", ->
    assert.isTrue RankingUtils.matches(["cat", "dog"], "catapult", "hound dog")

  should "every query term must match at least one thing (not matching)", ->
    assert.isTrue not RankingUtils.matches(["cat", "dog", "wolf"], "catapult", "hound dog")

context "RegexpCache",
  should "RegexpCache is in fact caching (positive case)", ->
    assert.isTrue RegexpCache.get("this") is RegexpCache.get("this")

  should "RegexpCache is in fact caching (negative case)", ->
    assert.isTrue RegexpCache.get("this") isnt RegexpCache.get("that")

  should "RegexpCache prefix/suffix wrapping is working (positive case)", ->
    assert.isTrue RegexpCache.get("this", "(", ")") is RegexpCache.get("this", "(", ")")

  should "RegexpCache prefix/suffix wrapping is working (negative case)", ->
    assert.isTrue RegexpCache.get("this", "(", ")") isnt RegexpCache.get("this")

  should "search for a string", ->
    assert.isTrue "hound dog".search(RegexpCache.get("dog")) == 6

  should "search for a string which isn't there", ->
    assert.isTrue "hound dog".search(RegexpCache.get("cat")) == -1

  should "search for a string with a prefix/suffix (positive case)", ->
    assert.isTrue "hound dog".search(RegexpCache.get("dog", "\\b", "\\b")) == 6

  should "search for a string with a prefix/suffix (negative case)", ->
    assert.isTrue "hound dog".search(RegexpCache.get("do", "\\b", "\\b")) == -1

fakeTimeDeltaElapsing = ->

context "TabRecency",
  setup ->
    @tabRecency = BgUtils.tabRecency

    fakeTimeDeltaElapsing = =>
      if @tabRecency.lastVisitedTime?
        @tabRecency.lastVisitedTime = new Date(@tabRecency.lastVisitedTime - @tabRecency.timeDelta)

    @tabRecency.register 3
    fakeTimeDeltaElapsing()
    @tabRecency.register 2
    fakeTimeDeltaElapsing()
    @tabRecency.register 9
    fakeTimeDeltaElapsing()
    @tabRecency.register 1
    @tabRecency.deregister 9
    fakeTimeDeltaElapsing()
    @tabRecency.register 4
    fakeTimeDeltaElapsing()

  should "have entries for recently active tabs", ->
    assert.isTrue @tabRecency.cache[1]
    assert.isTrue @tabRecency.cache[2]
    assert.isTrue @tabRecency.cache[3]

  should "not have entries for removed tabs", ->
    assert.isFalse @tabRecency.cache[9]

  should "give a high score to the most recent tab", ->
    assert.isTrue @tabRecency.recencyScore(4) < @tabRecency.recencyScore 1
    assert.isTrue @tabRecency.recencyScore(3) < @tabRecency.recencyScore 1
    assert.isTrue @tabRecency.recencyScore(2) < @tabRecency.recencyScore 1

  should "give a low score to the current tab", ->
    assert.isTrue @tabRecency.recencyScore(1) > @tabRecency.recencyScore 4
    assert.isTrue @tabRecency.recencyScore(2) > @tabRecency.recencyScore 4
    assert.isTrue @tabRecency.recencyScore(3) > @tabRecency.recencyScore 4

  should "rank tabs by recency", ->
    assert.isTrue @tabRecency.recencyScore(3) < @tabRecency.recencyScore 2
    assert.isTrue @tabRecency.recencyScore(2) < @tabRecency.recencyScore 1
    @tabRecency.register 3
    fakeTimeDeltaElapsing()
    @tabRecency.register 4 # Making 3 the most recent tab which isn't the current tab.
    assert.isTrue @tabRecency.recencyScore(1) < @tabRecency.recencyScore 3
    assert.isTrue @tabRecency.recencyScore(2) < @tabRecency.recencyScore 3
    assert.isTrue @tabRecency.recencyScore(4) < @tabRecency.recencyScore 3
    assert.isTrue @tabRecency.recencyScore(4) < @tabRecency.recencyScore 1
    assert.isTrue @tabRecency.recencyScore(4) < @tabRecency.recencyScore 2

# A convenience wrapper around completer.filter() so it can be called synchronously in tests.
filterCompleter = (completer, queryTerms) ->
  results = []
  completer.filter({ queryTerms, query: queryTerms.join " " }, (completionResults) -> results = completionResults)
  results

hours = (n) -> 1000 * 60 * 60 * n

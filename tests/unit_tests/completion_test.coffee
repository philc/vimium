require "./test_helper.js"
extend(global, require "../../lib/utils.js")
extend(global, require "../../background_scripts/completion.js")

global.chrome = {}

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

      should "found return the position if it's between two elements", ->
        assert.equal 1, HistoryCache.binarySearch(4, [3, 5, 8], @compare)
        assert.equal 2, HistoryCache.binarySearch(7, [3, 5, 8], @compare)

  context "fetchHistory",
    setup ->
      @history1 = { url: "b.com", lastVisitTime: 5 }
      @history2 = { url: "a.com", lastVisitTime: 10 }
      history = [@history1, @history2]
      @onVisitedListener = null
      global.chrome.history =
        search: (options, callback) -> callback(history)
        onVisited: { addListener: (@onVisitedListener) => }
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

context "history completer",
  setup ->
    @history1 = { title: "history1", url: "history1.com", lastVisitTime: hours(1) }
    @history2 = { title: "history2", url: "history2.com", lastVisitTime: hours(5) }

    global.chrome.history =
      search: (options, callback) => callback([@history1, @history2])
      onVisited: { addListener: -> }

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

    stub(HistoryCache, "use", (onComplete) => onComplete([@history1, @history2]))
    global.chrome.history = { onVisited: { addListener: -> } }
    stub(Date, "now", returns(hours(24)))

    @completer = new DomainCompleter()

  should "return only a single matching domain", ->
    results = filterCompleter(@completer, ["story"])
    assert.arrayEqual ["history1.com"], results.map (result) -> result.url

  should "pick domains which are more recent", ->
    # This domains are the same except for their last visited time.
    assert.equal "history1.com", filterCompleter(@completer, ["story"])[0].url
    @history2.lastVisitTime = hours(3)
    assert.equal "history2.com", filterCompleter(@completer, ["story"])[0].url

  should "returns no results when there's more than one query term, because clearly it's not a domain", ->
    assert.arrayEqual [], filterCompleter(@completer, ["his", "tory"])

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
    suggestion = new Suggestion(["queryterm"], "tab", "url", "title <span>", returns(1))
    assert.isTrue suggestion.generateHtml().indexOf("title &lt;span&gt;") >= 0

  should "highlight query words", ->
    suggestion = new Suggestion(["ninj", "words"], "tab", "url", "ninjawords", returns(1))
    expected = "<span class='vomnibarMatch'>ninj</span>a<span class='vomnibarMatch'>words</span>"
    assert.isTrue suggestion.generateHtml().indexOf(expected) >= 0

  should "highlight query words correctly when whey they overlap", ->
    suggestion = new Suggestion(["ninj", "jaword"], "tab", "url", "ninjawords", returns(1))
    expected = "<span class='vomnibarMatch'>ninjaword</span>s"
    assert.isTrue suggestion.generateHtml().indexOf(expected) >= 0

  should "shorten urls", ->
    suggestion = new Suggestion(["queryterm"], "tab", "http://ninjawords.com", "ninjawords", returns(1))
    assert.equal -1, suggestion.generateHtml().indexOf("http://ninjawords.com")

context "RankingUtils.wordRelevancy",
  should "get a higher relevancy score in shorter URLs", ->
    highScore = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/short",  "nothing")
    lowScore  = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/longer", "nothing")
    assert.isTrue highScore > lowScore

  should "get a higher relevancy score in shorter titles", ->
    highScore = RankingUtils.wordRelevancy(["ffee"], "http://stackoverflow.com/same", "Coffeescript")
    lowScore  = RankingUtils.wordRelevancy(["ffee"], "http://stackoverflow.com/same", "Coffeescript rocks")
    assert.isTrue highScore > lowScore

  should "get a higher relevancy score for matching the start of a word (in a URL)", ->
    lowScore  = RankingUtils.wordRelevancy(["stack"], "http://Xstackoverflow.com/same", "nothing")
    highScore = RankingUtils.wordRelevancy(["stack"], "http://stackoverflowX.com/same", "nothing")
    assert.isTrue highScore > lowScore

  should "get a higher relevancy score for matching the start of a word (in a title)", ->
    lowScore  = RankingUtils.wordRelevancy(["ted"], "http://stackoverflow.com/same", "Dist racted")
    highScore = RankingUtils.wordRelevancy(["ted"], "http://stackoverflow.com/same", "Distrac ted")
    assert.isTrue highScore > lowScore

  should "get a higher relevancy score for matching a whole word (in a URL)", ->
    lowScore  = RankingUtils.wordRelevancy(["com"], "http://stackoverflow.comX/same", "nothing")
    highScore = RankingUtils.wordRelevancy(["com"], "http://stackoverflowX.com/same", "nothing")
    assert.isTrue highScore > lowScore

  should "get a higher relevancy score for matching a whole word (in a title)", ->
    lowScore  = RankingUtils.wordRelevancy(["com"], "http://stackoverflow.com/same", "abc comX")
    highScore = RankingUtils.wordRelevancy(["com"], "http://stackoverflow.com/same", "abcX com")
    assert.isTrue highScore > lowScore

  # WARNING: The following tests may be hardware dependent.  They depend upon
  # different but algebraically-equivalent sequences of floating point
  # operations yielding the same results.  That they ever work at all is quite
  # remarkable.
  should "exactly equal oldWordRelevancy for whole word matches (in a URL)", ->
    newScore  = RankingUtils.wordRelevancy(["com"], "http://stackoverflow.com/same", "irrelevant")
    oldScore  = RankingUtils.oldWordRelevancy(["com"], "http://stackoverflow.com/same", "irrelevant")
    assert.isTrue newScore == oldScore # remarkable! Exactly equal floats.

  should "2/3 * oldWordRelevancy for matches at the start of a word (in a URL)", ->
    newScore  = RankingUtils.wordRelevancy(["sta"], "http://stackoverflow.com/same", "irrelevant")
    oldScore  = (2.0/3.0) * RankingUtils.oldWordRelevancy(["sta"], "http://stackoverflow.com/same", "irrelevant")
    assert.isTrue newScore == oldScore # remarkable! Exactly equal floats.

  should "1/3 * oldWordRelevancy for matches within a word (in a URL)", ->
    newScore  = RankingUtils.wordRelevancy(["over"], "http://stackoverflow.com/same", "irrelevant")
    oldScore  = (1.0/3.0) * RankingUtils.oldWordRelevancy(["over"], "http://stackoverflow.com/same", "irrelevant")
    assert.isTrue newScore == oldScore # remarkable! Exactly equal floats.

  should "exactly equal oldWordRelevancy for whole word matches (in a title)", ->
    newScore  = RankingUtils.wordRelevancy(["relevant"], "http://stackoverflow.com/same", "XX relevant YY")
    # Multiply by 2 to account for new wordRelevancy favoring title.
    oldScore  = 2 * RankingUtils.oldWordRelevancy(["relevant"], "http://stackoverflow.com/same", "XX relevant YY")
    assert.isTrue newScore == oldScore  # remarkable! Exactly equal floats.

  should "2/3 * oldWordRelevancy for matches at the start of a word (in a title)", ->
    newScore  = RankingUtils.wordRelevancy(["relev"], "http://stackoverflow.com/same", "XX relevant YY")
    # Multiply by 2 to account for new wordRelevancy favoring title.
    oldScore  = (2.0/3.0) * 2 * RankingUtils.oldWordRelevancy(["relev"], "http://stackoverflow.com/same", "XX relevant YY")
    assert.isTrue newScore == oldScore  # remarkable! Exactly equal floats.

  should "1/3 * oldWordRelevancy for matches within a word (in a title)", ->
    newScore  = RankingUtils.wordRelevancy(["elev"], "http://stackoverflow.com/same", "XX relevant YY")
    # Multiply by 2 to account for new wordRelevancy favoring title.
    oldScore  = (1.0/3.0) * 2 * RankingUtils.oldWordRelevancy(["elev"], "http://stackoverflow.com/same", "XX relevant YY")
    assert.isTrue newScore == oldScore  # remarkable! Exactly equal floats.
  #
  # End of possibly hardware-dependent tests.

  # # TODO: (smblott)
  # #       Word relevancy should take into account the number of matches (it doesn't currently).
  # should "get a higher relevancy score for multiple matches (in a URL)", ->
  #   lowScore  = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/Xxxxxx", "nothing")
  #   highScore = RankingUtils.wordRelevancy(["stack"], "http://stackoverflow.com/Xstack", "nothing")
  #   assert.isTrue highScore > lowScore

  # should "get a higher relevancy score for multiple matches (in a title)", ->
  #   lowScore  = RankingUtils.wordRelevancy(["bbc"], "http://stackoverflow.com/same", "BBC Radio 4 (XBCr4)")
  #   highScore = RankingUtils.wordRelevancy(["bbc"], "http://stackoverflow.com/same", "BBC Radio 4 (BBCr4)")
  #   assert.isTrue highScore > lowScore

context "RankingUtils",
  should "do a case insensitive match", ->
    assert.isTrue RankingUtils.matches(["aRi"], "MARIO", "MARio")

  should "do a case insensitive match on full term", ->
    assert.isTrue RankingUtils.matches(["MaRiO"], "MARIO", "MARio")

  should "do a case insensitive match on more than just two terms", ->
    assert.isTrue RankingUtils.matches(["aRi"], "DOES_NOT_MATCH", "DOES_NOT_MATCH_EITHER", "MARio")

  should "do case insensitive word relevancy (matching)", ->
    assert.isTrue RankingUtils.wordRelevancy(["aRi"], "MARIO", "MARio") > 0.0

  should "do case insensitive word relevancy (not matching)", ->
    assert.isTrue RankingUtils.wordRelevancy(["DOES_NOT_MATCH"], "MARIO", "MARio") == 0.0

  should "every term must match at least one thing (matching)", ->
    assert.isTrue RankingUtils.matches(["cat", "dog"], "catapult", "hound dog")

  should "every term must match at least one thing (not matching)", ->
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

# A convenience wrapper around completer.filter() so it can be called synchronously in tests.
filterCompleter = (completer, queryTerms) ->
  results = []
  completer.filter(queryTerms, (completionResults) -> results = completionResults)
  results

hours = (n) -> 1000 * 60 * 60 * n

require "./test_helper.js"
extend(global, require "../lib/utils.js")
extend(global, require "../background_scripts/completion.js")

global.chrome = {}

context "bookmark completer",
  setup ->
    @bookmark2 = { title: "bookmark2", url: "bookmark2.com" }
    @bookmark1 = { title: "bookmark1", url: "bookmark1.com", children: [@bookmark2] }
    global.chrome.bookmarks =
      getTree: (callback) => callback([@bookmark1])

    @completer = new BookmarkCompleter()

  should "flatten a list of bookmarks", ->
    result = @completer.traverseBookmarks([@bookmark1])
    assert.arrayEqual [@bookmark1, @bookmark2], @completer.traverseBookmarks([@bookmark1])

  should "return matching bookmarks when searching", ->
    @completer.refresh()
    @completer.filter(["mark2"], (@results) =>)
    assert.arrayEqual [@bookmark2.url], @results.map (suggestion) -> suggestion.url

context "history completer",
  setup ->
    # history2 is more recent than history1.
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

context "suggestions",
  should "escape html in page titles", ->
    suggestion = new Suggestion(["queryterm"], "tab", "url", "title <span>", returns(1))
    assert.isTrue suggestion.generateHtml().indexOf("title &lt;span&gt;") >= 0

  should "highlight query words", ->
    suggestion = new Suggestion(["ninj", "words"], "tab", "url", "ninjawords", returns(1))
    expected = "<span class='match'>ninj</span>a<span class='match'>words</span>"
    assert.isTrue suggestion.generateHtml().indexOf(expected) >= 0

  should "highlight query words correctly when whey they overlap", ->
    suggestion = new Suggestion(["ninj", "jaword"], "tab", "url", "ninjawords", returns(1))
    expected = "<span class='match'>ninjaword</span>s"
    assert.isTrue suggestion.generateHtml().indexOf(expected) >= 0

  should "shorten urls", ->
    suggestion = new Suggestion(["queryterm"], "tab", "http://ninjawords.com", "ninjawords", returns(1))
    assert.equal -1, suggestion.generateHtml().indexOf("http://ninjawords.com")

# A convenience wrapper around completer.filter() so it can be called synchronously in tests.
filterCompleter = (completer, queryTerms) ->
  results = []
  completer.filter(queryTerms, (completionResults) -> results = completionResults)
  results

hours = (n) -> 1000 * 60 * 60 * n

Tests.run()
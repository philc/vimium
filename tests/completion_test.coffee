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
    @completer.filter(["story1"], (@results) =>)
    assert.arrayEqual [@history1.url], @results.map (entry) -> entry.url

  should "rank recent results higher than nonrecent results", ->
    stub(Date, "now", returns(hours(24)))
    @completer.filter(["hist"], (@results) =>)
    @results.forEach (result) -> result.computeRelevancy()
    @results.sort (a, b) -> b.relevancy - a.relevancy
    assert.arrayEqual [@history2.url, @history1.url], @results.map (result) -> result.url

context "suggestions",
  should "escape html in page titles", ->
    suggestion = new Suggestion(["queryterm"], "tab", "url", "title <span>", returns(1))
    assert.isTrue suggestion.generateHtml().indexOf("title &lt;span&gt;") >= 0

  should "highlight query words", ->
    suggestion = new Suggestion(["ninja"], "tab", "url", "ninjawords", returns(1))
    assert.isTrue suggestion.generateHtml().indexOf("<span class='match'>ninja</span>words") >= 0

  should "shorten urls", ->
    suggestion = new Suggestion(["queryterm"], "tab", "http://ninjawords.com", "ninjawords", returns(1))
    assert.equal -1, suggestion.generateHtml().indexOf("http://ninjawords.com")

hours = (n) -> 1000 * 60 * 60 * n

Tests.run()
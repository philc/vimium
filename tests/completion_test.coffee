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
    @history1 = { title: "history1", url: "history1.com" }
    @history2 = { title: "history2", url: "history2.com" }

    global.chrome.history =
      search: (options, callback) => callback([@history1, @history2])
      onVisited: { addListener: -> }

    @completer = new HistoryCompleter()

  should "return matching history entries when searching", ->
    @completer.filter(["story1"], (@results) =>)
    assert.arrayEqual [@history1.url], @results.map (entry) -> entry.url

context "suggestions",
  should "escape html in page titles", ->
    suggestion = new Suggestion(["queryterm"], "tab", "url", "title <span>", "action")
    assert.isTrue suggestion.generateHtml().indexOf("title &lt;span&gt;") >= 0

  should "highlight query words", ->
    suggestion = new Suggestion(["ninja"], "tab", "url", "ninjawords", "action")
    assert.isTrue suggestion.generateHtml().indexOf("<span class='match'>ninja</span>words") >= 0

  should "shorten urls", ->
    suggestion = new Suggestion(["queryterm"], "tab", "http://ninjawords.com", "ninjawords", "action")
    assert.equal -1, suggestion.generateHtml().indexOf("http://ninjawords.com")

Tests.run()
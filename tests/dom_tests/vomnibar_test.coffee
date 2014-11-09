context "Keep selection within bounds",

  setup ->
    @completions = []
    @faviconId = "1234"
    @html = '<img id="' + @faviconId + '" src=""/>'
    oldGetCompleter = Vomnibar.getCompleter.bind Vomnibar
    stub Vomnibar, 'getCompleter', (name) =>
      completer = oldGetCompleter name
      stub completer, 'filter', (query, callback) => callback(@completions)
      completer

  tearDown ->
    Vomnibar.vomnibarUI.hide()

  should "set selection to position -1 for omni completion by default", ->
    Vomnibar.activate()
    ui = Vomnibar.vomnibarUI

    @completions = []
    ui.update(true)
    assert.equal -1, ui.selection

    @completions = [{html:@html,type:'tab',url:'http://example.com',faviconId:@faviconId}]
    ui.update(true)
    assert.equal -1, ui.selection

    @completions = []
    ui.update(true)
    assert.equal -1, ui.selection

  should "set selection to position 0 for bookmark completion if possible", ->
    Vomnibar.activateBookmarks()
    ui = Vomnibar.vomnibarUI

    @completions = []
    ui.update(true)
    assert.equal -1, ui.selection

    @completions = [{html:@html,type:'bookmark',url:'http://example.com',faviconId:@faviconId}]
    ui.update(true)
    assert.equal 0, ui.selection

    @completions = []
    ui.update(true)
    assert.equal -1, ui.selection

  should "keep selection within bounds", ->
    Vomnibar.activate()
    ui = Vomnibar.vomnibarUI

    @completions = []
    ui.update(true)

    eventMock =
      preventDefault: ->
      stopImmediatePropagation: ->

    @completions = [{html:@html,type:'tab',url:'http://example.com',faviconId:@faviconId}]
    ui.update(true)
    stub ui, "actionFromKeyEvent", -> "down"
    ui.onKeydown eventMock
    assert.equal 0, ui.selection

    @completions = []
    ui.update(true)
    assert.equal -1, ui.selection

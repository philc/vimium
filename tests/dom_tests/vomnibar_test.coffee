context "Keep selection within bounds",

  setup ->
    @completions = []
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

    @completions = [{html:'foo',type:'tab',url:'http://example.com'}]
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

    @completions = [{html:'foo',type:'bookmark',url:'http://example.com'}]
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
      stopPropagation: ->

    @completions = [{html:'foo',type:'tab',url:'http://example.com'}]
    ui.update(true)
    stub ui, "actionFromKeyEvent", -> "down"
    ui.onKeydown eventMock
    assert.equal 0, ui.selection

    @completions = []
    ui.update(true)
    assert.equal -1, ui.selection

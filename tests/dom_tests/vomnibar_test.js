let vomnibarFrame = null;
Vomnibar.init();

context("Keep selection within bounds", () => {

  setup(() => {
    this.completions = [];

    vomnibarFrame = Vomnibar.vomnibarUI.iframeElement.contentWindow;

    // The Vomnibar frame is dynamically injected, so inject our stubs here.
    vomnibarFrame.chrome = chrome;

    const oldGetCompleter = vomnibarFrame.Vomnibar.getCompleter.bind(vomnibarFrame.Vomnibar);
    stub(vomnibarFrame.Vomnibar, 'getCompleter', name => {
      const completer = oldGetCompleter(name);
      stub(completer, 'filter', ({ callback }) => callback({results: this.completions}));
      return completer;
    });

    // Shoulda.js doesn't support async tests, so we have to hack around.
    stub(Vomnibar.vomnibarUI, "hide", () => {});
    stub(Vomnibar.vomnibarUI, "postMessage", data => vomnibarFrame.UIComponentServer.handleMessage({data}));
    stub(vomnibarFrame.UIComponentServer, "postMessage", data => UIComponent.handleMessage({data}));}),

  tearDown(() => Vomnibar.vomnibarUI.hide()),

  should("set selection to position -1 for omni completion by default", () => {
    Vomnibar.activate(0, {options: {}});
    const ui = vomnibarFrame.Vomnibar.vomnibarUI;

    this.completions = [];
    ui.update(true);
    assert.equal(-1, ui.selection);

    this.completions = [{html:'foo',type:'tab',url:'http://example.com'}];
    ui.update(true);
    assert.equal(-1, ui.selection);

    this.completions = [];
    ui.update(true);
    assert.equal(-1, ui.selection);
  });

  should("set selection to position 0 for bookmark completion if possible", () => {
    Vomnibar.activateBookmarks();
    const ui = vomnibarFrame.Vomnibar.vomnibarUI;

    this.completions = [];
    ui.update(true);
    assert.equal(-1, ui.selection);

    this.completions = [{html:'foo',type:'bookmark',url:'http://example.com'}];
    ui.update(true);
    assert.equal(0, ui.selection);

    this.completions = [];
    ui.update(true);
    assert.equal(-1, ui.selection);
  });

  should("keep selection within bounds", () => {
    Vomnibar.activate(0, {options: {}});
    const ui = vomnibarFrame.Vomnibar.vomnibarUI;

    this.completions = [];
    ui.update(true);

    const eventMock = {
      preventDefault() {},
      stopImmediatePropagation() {}
    };

    this.completions = [{html:'foo',type:'tab',url:'http://example.com'}];
    ui.update(true);
    stub(ui, "actionFromKeyEvent", () => "down");
    ui.onKeyEvent(eventMock);
    assert.equal(0, ui.selection);

    this.completions = [];
    ui.update(true);
    assert.equal(-1, ui.selection);
  })
});

import "./test_helper.js";
import "../../background_scripts/tab_recency.js";

context("TabRecency", () => {
  let tabRecency;

  setup(() => tabRecency = new TabRecency());

  context("order", () => {
    setup(async () => {
      stub(chrome.tabs, "query", () => Promise.resolve([]));
      await tabRecency.init();
      tabRecency.queueAction("register", (1));
      tabRecency.queueAction("register", (2));
      tabRecency.queueAction("register", (3));
      tabRecency.queueAction("register", (4));
      tabRecency.queueAction("deregister", (4));
      tabRecency.queueAction("register", (2));
    });

    should("have the correct entries in the correct order", () => {
      const expected = [2, 3, 1];
      assert.equal(expected, tabRecency.getTabsByRecency());
    });

    should("score tabs by recency; current tab should be last", () => {
      const score = (id) => tabRecency.recencyScore(id);
      assert.equal(0, score(2));
      assert.isTrue(score(2) < score(1));
      assert.isTrue(score(1) < score(3));
    });
  });

  should("navigate actions are queued until state from storage is loaded", async () => {
    let onActivated;
    stub(chrome.tabs.onActivated, "addListener", (fn) => {
      onActivated = fn;
    });
    let resolveStorage;
    const storagePromise = new Promise((resolve, _) => resolveStorage = resolve);
    stub(chrome.storage.session, "get", () => storagePromise);
    tabRecency.init();
    // Here, chrome.tabs.onActivated listeners have been added by tabrecency, but the
    // chrome.storage.session data hasn't yet loaded.
    onActivated({ tabId: 5 });
    resolveStorage({});
    await tabRecency.init();
    assert.equal([5], tabRecency.getTabsByRecency());
  });

  should("loadFromStorage handles empty values", async () => {
    stub(chrome.tabs, "query", () => Promise.resolve([{ id: 1 }]));

    stub(chrome.storage.session, "get", () => Promise.resolve({}));
    await tabRecency.init();
    assert.equal([], tabRecency.getTabsByRecency());

    stub(chrome.storage.session, "get", () => Promise.resolve({ tabRecency: {} }));
    await tabRecency.loadFromStorage();
    assert.equal([], tabRecency.getTabsByRecency());
  });

  should("loadFromStorage works", async () => {
    const tabs = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }];
    stub(chrome.tabs, "query", () => Promise.resolve(tabs));

    const storage = { tabRecency: { 1: 5, 2: 6 } };
    stub(chrome.storage.session, "get", () => Promise.resolve(storage));

    // Even though the in-storage tab counters are higher than the in-memory tabs, during
    // loading, the in-memory tab counters are adjusted to be the most recent.
    await tabRecency.init();

    assert.equal([2, 1], tabRecency.getTabsByRecency());

    tabRecency.queueAction("register", (3));
    tabRecency.queueAction("register", (1));

    assert.equal([1, 3, 2], tabRecency.getTabsByRecency());
  });

  should("loadFromStorage prunes out tabs which are no longer active", async () => {
    const tabs = [{ id: 1 }];
    stub(chrome.tabs, "query", () => Promise.resolve(tabs));

    const storage = { tabRecency: { 1: 5, 2: 6 } };
    stub(chrome.storage.session, "get", () => Promise.resolve(storage));
    await tabRecency.init();
    assert.equal([1], tabRecency.getTabsByRecency());
  });
});

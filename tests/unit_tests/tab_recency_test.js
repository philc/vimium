import "./test_helper.js";
import * as tabRecency from "../../background_scripts/tab_recency.js";

context("TabRecency", () => {
  let tracker;

  setup(() => tracker = new tabRecency.Tracker());

  context("order", () => {
    setup(async () => {
      stub(chrome.tabs, "query", () => Promise.resolve([]));
      await tracker.init();
      tracker.queueAction("register", 1);
      tracker.queueAction("register", 2);
      tracker.queueAction("register", 3);
      tracker.queueAction("register", 4);
      tracker.queueAction("deregister", 4);
      tracker.queueAction("register", 2);
    });

    should("have the correct entries in the correct order", () => {
      const expected = [2, 3, 1];
      assert.equal(expected, tracker.getTabsByRecency());
    });

    should("score tabs by recency; current tab should be last", () => {
      const score = (id) => tracker.recencyScore(id);
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
    tracker.init();
    // Here, chrome.tabs.onActivated listeners have been added by tabrecency, but the
    // chrome.storage.session data hasn't yet loaded.
    onActivated({ tabId: 5 });
    resolveStorage({});
    await tracker.init();
    assert.equal([5], tracker.getTabsByRecency());
  });

  should("loadFromStorage handles empty values", async () => {
    stub(chrome.tabs, "query", () => Promise.resolve([{ id: 1 }]));

    stub(chrome.storage.session, "get", () => Promise.resolve({}));
    await tracker.init();
    assert.equal([], tracker.getTabsByRecency());

    stub(chrome.storage.session, "get", () => Promise.resolve({ tabRecency: {} }));
    await tracker.loadFromStorage();
    assert.equal([], tracker.getTabsByRecency());
  });

  should("loadFromStorage works", async () => {
    const tabs = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }];
    stub(chrome.tabs, "query", () => Promise.resolve(tabs));

    const storage = { tabRecency: { 1: 5, 2: 6 } };
    stub(chrome.storage.session, "get", () => Promise.resolve(storage));

    // Even though the in-storage tab counters are higher than the in-memory tabs, during
    // loading, the in-memory tab counters are adjusted to be the most recent.
    await tracker.init();

    assert.equal([2, 1], tracker.getTabsByRecency());

    tracker.queueAction("register", 3);
    tracker.queueAction("register", 1);

    assert.equal([1, 3, 2], tracker.getTabsByRecency());
  });

  should("loadFromStorage prunes out tabs which are no longer active", async () => {
    const tabs = [{ id: 1 }];
    stub(chrome.tabs, "query", () => Promise.resolve(tabs));

    const storage = { tabRecency: { 1: 5, 2: 6 } };
    stub(chrome.storage.session, "get", () => Promise.resolve(storage));
    await tracker.init();
    assert.equal([1], tracker.getTabsByRecency());
  });
});

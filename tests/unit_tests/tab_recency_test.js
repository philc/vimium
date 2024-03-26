import "./test_helper.js";
import "../../background_scripts/tab_recency.js";

context("TabRecency", () => {
  let tabRecency;

  setup(() => tabRecency = new TabRecency());

  context("order", () => {
    setup(() => {
      tabRecency.register(1);
      tabRecency.register(2);
      tabRecency.register(3);
      tabRecency.register(4);
      tabRecency.deregister(4);
      tabRecency.register(2);
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

  should("loadFromStorage handles empty values", async () => {
    stub(chrome.tabs, "query", () => Promise.resolve([{ id: 1 }]));

    stub(chrome.storage.session, "get", () => Promise.resolve({}));
    await tabRecency.loadFromStorage();
    assert.equal([], tabRecency.getTabsByRecency());

    stub(chrome.storage.session, "get", () => Promise.resolve({ tabRecency: {} }));
    await tabRecency.loadFromStorage();
    assert.equal([], tabRecency.getTabsByRecency());
  });

  should("loadFromStorage merges in-memory tabs with in-storage tabs", async () => {
    const tabs = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }];
    stub(chrome.tabs, "query", () => Promise.resolve(tabs));

    tabRecency.register(3);
    tabRecency.register(4);

    const storage = { tabRecency: { 1: 5, 2: 6 } };
    stub(chrome.storage.session, "get", () => Promise.resolve(storage));

    // Even though the in-storage tab counters are higher than the in-memory tabs, during
    // loading, the in-memory tab counters are adjusted to be the most recent.
    await tabRecency.loadFromStorage();

    assert.equal([4, 3, 2, 1], tabRecency.getTabsByRecency());
  });

  should("loadFromStorage prunes out tabs which are no longer active", async () => {
    const tabs = [{ id: 1 }];
    stub(chrome.tabs, "query", () => Promise.resolve(tabs));

    const storage = { tabRecency: { 1: 5, 2: 6 } };
    stub(chrome.storage.session, "get", () => Promise.resolve(storage));
    await tabRecency.loadFromStorage();
    assert.equal([1], tabRecency.getTabsByRecency());
  });
});

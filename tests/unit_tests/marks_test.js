import "./test_helper.js";
import "../../background_scripts/marks.js";

context("marks", () => {
  const createMark = async (markProperties, tabProperties) => {
    const mark = Object.assign({ scrollX: 0, scrollY: 0 }, markProperties);
    const tab = Object.assign({ url: "http://example.com" }, tabProperties);
    const sender = { tab: tab };
    await Marks.create(mark, sender);
  };

  setup(() => {
    chrome.storage.session.clear();
    chrome.storage.session.set({ vimiumSecret: "secret" });
  });

  teardown(() => {
    chrome.storage.session.clear();
    chrome.storage.local.clear();
  });

  should("record the vimium secret in the mark's info", async () => {
    await createMark({ markName: "a" });
    const key = Marks.getLocationKey("a");
    const savedMark = (await chrome.storage.local.get(key))[key];
    assert.equal("secret", savedMark.vimiumSecret);
  });

  should("goto a mark when its tab exists", async () => {
    await createMark({ markName: "A" }, { id: 1 });
    const tab = { url: "http://example.com" };
    stub(window.chrome.tabs, "get", (id) => id == 1 ? tab : null);
    const updatedTabs = [];
    stub(window.chrome.tabs, "update", (id, properties) => updatedTabs[id] = properties);
    await Marks.goto({ markName: "A" });
    assert.isTrue(updatedTabs[1] && updatedTabs[1].active);
  });

  should("find a new tab if a mark's tab no longer exists", async () => {
    await createMark({ markName: "A" }, { id: 1 });
    const tab = { url: "http://example.com", id: 2 };
    stub(window.chrome.tabs, "get", (_id) => {
      throw new Error();
    });
    stub(window.chrome.tabs, "query", (_) => [tab]);
    const updatedTabs = [];
    stub(window.chrome.tabs, "update", (id, properties) => updatedTabs[id] = properties);
    await Marks.goto({ markName: "A" });
    assert.isTrue(updatedTabs[2] && updatedTabs[2].active);
  });
});

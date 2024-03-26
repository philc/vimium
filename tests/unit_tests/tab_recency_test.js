import "./test_helper.js";
import "../../background_scripts/tab_recency.js";

context("TabRecency", () => {
  let tabRecency;

  setup(() => {
    tabRecency = new TabRecency();
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

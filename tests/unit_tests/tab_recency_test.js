import "./test_helper.js";
import "../../background_scripts/tab_recency.js";
import "../../background_scripts/bg_utils.js";

let fakeTimeDeltaElapsing = () => {};

context("TabRecency", () => {
  const tabRecency = BgUtils.tabRecency;

  setup(() => {
    fakeTimeDeltaElapsing = () => {
      if (tabRecency.lastVisitedTime != null) {
        tabRecency.lastVisitedTime = new Date(tabRecency.lastVisitedTime - TabRecency.TIME_DELTA);
      }
    };

    tabRecency.register(3);
    fakeTimeDeltaElapsing();
    tabRecency.register(2);
    fakeTimeDeltaElapsing();
    tabRecency.register(9);
    fakeTimeDeltaElapsing();
    tabRecency.register(1);
    tabRecency.deregister(9);
    fakeTimeDeltaElapsing();
    tabRecency.register(4);
    fakeTimeDeltaElapsing();
  });

  should("have entries for recently active tabs", () => {
    assert.isTrue(tabRecency.cache[1]);
    assert.isTrue(tabRecency.cache[2]);
    assert.isTrue(tabRecency.cache[3]);
  });

  should("not have entries for removed tabs", () => {
    assert.isFalse(tabRecency.cache[9]);
  });

  should("give a high score to the most recent tab", () => {
    assert.isTrue(tabRecency.recencyScore(4) < tabRecency.recencyScore(1));
    assert.isTrue(tabRecency.recencyScore(3) < tabRecency.recencyScore(1));
    assert.isTrue(tabRecency.recencyScore(2) < tabRecency.recencyScore(1));
  });

  should("give a low score to the current tab", () => {
    assert.isTrue(tabRecency.recencyScore(1) > tabRecency.recencyScore(4));
    assert.isTrue(tabRecency.recencyScore(2) > tabRecency.recencyScore(4));
    assert.isTrue(tabRecency.recencyScore(3) > tabRecency.recencyScore(4));
  });

  should("rank tabs by recency", () => {
    assert.isTrue(tabRecency.recencyScore(3) < tabRecency.recencyScore(2));
    assert.isTrue(tabRecency.recencyScore(2) < tabRecency.recencyScore(1));
    tabRecency.register(3);
    fakeTimeDeltaElapsing();
    tabRecency.register(4); // Making 3 the most recent tab which isn't the current tab.
    assert.isTrue(tabRecency.recencyScore(1) < tabRecency.recencyScore(3));
    assert.isTrue(tabRecency.recencyScore(2) < tabRecency.recencyScore(3));
    assert.isTrue(tabRecency.recencyScore(4) < tabRecency.recencyScore(3));
    assert.isTrue(tabRecency.recencyScore(4) < tabRecency.recencyScore(1));
    assert.isTrue(tabRecency.recencyScore(4) < tabRecency.recencyScore(2));
  });
});

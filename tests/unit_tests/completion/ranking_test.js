import "../test_helper.js";
import * as ranking from "../../../background_scripts/completion/ranking.js";
import { RegexpCache } from "../../../background_scripts/completion/ranking.js";
import "../../../lib/url_utils.js";

context("wordRelevancy", () => {
  should("score higher in shorter URLs", () => {
    const highScore = ranking.wordRelevancy(
      ["stack"],
      "http://stackoverflow.com/short",
      "a-title",
    );
    const lowScore = ranking.wordRelevancy(
      ["stack"],
      "http://stackoverflow.com/longer",
      "a-title",
    );
    assert.isTrue(highScore > lowScore);
  });

  should("score higher in shorter titles", () => {
    const highScore = ranking.wordRelevancy(["milk"], "a-url", "Milkshakes");
    const lowScore = ranking.wordRelevancy(["milk"], "a-url", "Milkshakes rocks");
    assert.isTrue(highScore > lowScore);
  });

  should("score higher for matching the start of a word (in a URL)", () => {
    const lowScore = ranking.wordRelevancy(
      ["stack"],
      "http://Xstackoverflow.com/same",
      "a-title",
    );
    const highScore = ranking.wordRelevancy(
      ["stack"],
      "http://stackoverflowX.com/same",
      "a-title",
    );
    assert.isTrue(highScore > lowScore);
  });

  should("score higher for matching the start of a word (in a title)", () => {
    const lowScore = ranking.wordRelevancy(["te"], "a-url", "Dist racted");
    const highScore = ranking.wordRelevancy(["te"], "a-url", "Distrac ted");
    assert.isTrue(highScore > lowScore);
  });

  should("score higher for matching a whole word (in a URL)", () => {
    const lowScore = ranking.wordRelevancy(
      ["com"],
      "http://stackoverflow.comX/same",
      "a-title",
    );
    const highScore = ranking.wordRelevancy(
      ["com"],
      "http://stackoverflowX.com/same",
      "a-title",
    );
    assert.isTrue(highScore > lowScore);
  });

  should("score higher for matching a whole word (in a title)", () => {
    const lowScore = ranking.wordRelevancy(["com"], "a-url", "abc comX");
    const highScore = ranking.wordRelevancy(["com"], "a-url", "abcX com");
    assert.isTrue(highScore > lowScore);
  });
});

context("matches", () => {
  should("do a case insensitive match", () => {
    assert.isTrue(ranking.matches(["ari"], "maRio"));
  });

  should("do a case insensitive match on full term", () => {
    assert.isTrue(ranking.matches(["mario"], "MARio"));
  });

  should("do a case insensitive match on several terms", () => {
    assert.isTrue(
      ranking.matches(["ari"], "DOES_NOT_MATCH", "DOES_NOT_MATCH_EITHER", "MARio"),
    );
  });

  should("do a smartcase match (positive)", () => {
    assert.isTrue(ranking.matches(["Mar"], "Mario"));
  });

  should("do a smartcase match (negative)", () => {
    assert.isFalse(ranking.matches(["Mar"], "mario"));
  });

  should("do a match with regexp meta-characters (positive)", () => {
    assert.isTrue(ranking.matches(["ma.io"], "ma.io"));
  });

  should("do a match with regexp meta-characters (negative)", () => {
    assert.isFalse(ranking.matches(["ma.io"], "mario"));
  });

  should("do a smartcase match on full term", () => {
    assert.isTrue(ranking.matches(["Mario"], "Mario"));
    assert.isFalse(ranking.matches(["Mario"], "mario"));
  });

  should("do case insensitive word relevancy (matching)", () => {
    assert.isTrue(ranking.wordRelevancy(["ari"], "MARIO", "MARio") > 0.0);
  });

  should("do case insensitive word relevancy (not matching)", () => {
    assert.isTrue(ranking.wordRelevancy(["DOES_NOT_MATCH"], "MARIO", "MARio") === 0.0);
  });

  should("every query term must match at least one thing (matching)", () => {
    assert.isTrue(ranking.matches(["cat", "dog"], "catapult", "hound dog"));
  });

  should("every query term must match at least one thing (not matching)", () => {
    assert.isTrue(!ranking.matches(["cat", "dog", "wolf"], "catapult", "hound dog"));
  });
});

context("RegexpCache", () => {
  should("RegexpCache is in fact caching (positive case)", () => {
    assert.isTrue(RegexpCache.get("this") === RegexpCache.get("this"));
  });

  should("RegexpCache is in fact caching (negative case)", () => {
    assert.isTrue(RegexpCache.get("this") !== RegexpCache.get("that"));
  });

  should("RegexpCache prefix/suffix wrapping is working (positive case)", () => {
    assert.isTrue(RegexpCache.get("this", "(", ")") === RegexpCache.get("this", "(", ")"));
  });

  should("RegexpCache prefix/suffix wrapping is working (negative case)", () => {
    assert.isTrue(RegexpCache.get("this", "(", ")") !== RegexpCache.get("this"));
  });

  should("search for a string", () => {
    assert.isTrue("hound dog".search(RegexpCache.get("dog")) === 6);
  });

  should("search for a string which isn't there", () => {
    assert.isTrue("hound dog".search(RegexpCache.get("cat")) === -1);
  });

  should("search for a string with a prefix/suffix (positive case)", () => {
    assert.isTrue("hound dog".search(RegexpCache.get("dog", "\\b", "\\b")) === 6);
  });

  should("search for a string with a prefix/suffix (negative case)", () => {
    assert.isTrue("hound dog".search(RegexpCache.get("do", "\\b", "\\b")) === -1);
  });
});

import "./test_helper.js";
import "../../background_scripts/bg_utils.js";
import * as Engines from "../../background_scripts/completion_engines.js";
import "../../background_scripts/completion.js";

context("Amazon completion", () => {
  should("parses results", () => {
    const response = JSON.stringify({
      "suggestions": [
        { "value": "one" },
        { "value": "two" },
      ],
    });
    const results = new Engines.Amazon().parse(response);
    assert.equal(["one", "two"], results);
  });
});

context("Brave completion", () => {
  should("parses results", () => {
    const response = JSON.stringify(["the-query", ["one", "two"]]);
    const results = new Engines.Brave().parse(response);
    assert.equal(["one", "two"], results);
  });
});

context("DuckDuckGo completion", () => {
  should("parses results", () => {
    const response = JSON.stringify([
      { "phrase": "one" },
      { "phrase": "two" },
    ]);
    const results = new Engines.DuckDuckGo().parse(response);
    assert.equal(["one", "two"], results);
  });
});

context("Qwant completion", () => {
  should("parses results", () => {
    const response = JSON.stringify({
      "data": {
        "items": [
          { "value": "one" },
          { "value": "two" },
        ],
      },
    });
    const results = new Engines.Qwant().parse(response);
    assert.equal(["one", "two"], results);
  });
});

// Engines which have trivial parsers are omitted from these tests.
context("Webster completion", () => {
  should("parses results", () => {
    const response = JSON.stringify({
      "docs": [
        { "word": "one" },
        { "word": "two" },
      ],
    });
    const results = new Engines.Webster().parse(response);
    assert.equal(["one", "two"], results);
  });
});

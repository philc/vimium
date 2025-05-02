import "./test_helper.js";

import * as userSearchEngines from "../../background_scripts/user_search_engines.js";
import { UserSearchEngine } from "../../background_scripts/user_search_engines.js";

context("UserSearchEngines", () => {
  should("parse out search engine text", () => {
    const config = [
      "g: http://google.com/%s Google Search",
      "random line",
      "# comment",
      " w: http://wikipedia.org/%s",
    ].join("\n");

    const results = userSearchEngines.parseConfig(config).keywordToEngine;

    assert.equal(
      {
        g: new UserSearchEngine({
          keyword: "g",
          url: "http://google.com/%s",
          description: "Google Search",
        }),
        w: new UserSearchEngine({
          keyword: "w",
          url: "http://wikipedia.org/%s",
          description: "search (w)",
        }),
      },
      results,
    );
  });

  should("return validation errors", () => {
    const getErrors = (config) => userSearchEngines.parseConfig(config).validationErrors;
    assert.equal(0, getErrors("g: http://google.com").length);
    // Missing colon.
    assert.equal(1, getErrors("g http://google.com").length);
    // Not enough tokens.
    assert.equal(1, getErrors("g:").length);
    // Invalid search engine URL.
    assert.equal(1, getErrors("g: invalid-url").length);
  });
});

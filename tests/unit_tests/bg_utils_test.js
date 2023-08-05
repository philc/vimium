import "./test_helper.js";

import "../../background_scripts/bg_utils.js";

context("UserSearchEngines", () => {
  should("parse out search engine text", () => {
    const config = [
      "g: http://google.com/%s Google Search",
      "random line",
      "# comment",
      " w: http://wikipedia.org/%s",
    ].join("\n");

    const results = UserSearchEngines.parseConfig(config);

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
});

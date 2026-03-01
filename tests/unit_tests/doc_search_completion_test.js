import * as testHelper from "./test_helper.js";
import "../../tests/unit_tests/test_chrome_stubs.js";
import "../../lib/utils.js";
import "../../lib/settings.js";
import * as completionEngines from "../../background_scripts/completion/search_engines.js";
import * as page from "../../pages/doc_search_completion.js";

context("completion engines page", () => {
  setup(async () => {
    await testHelper.jsdomStub("pages/doc_search_completion.html");
  });

  should("have a section in the html for every engine", () => {
    // This is to prevent editing errors, where a new command group is added, and we forget to add a
    // corresponding group to the command listing.
    page.populatePage();
    const engines = completionEngines.list.map((e) => e.name);
    const enginesInPage = Array.from(globalThis.document.querySelectorAll("h4[data-engine]"))
      .map((e) => e.dataset.engine);
    assert.equal(engines, enginesInPage);
  });
});

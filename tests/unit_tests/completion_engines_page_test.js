import "./test_helper.js";
import * as jsdom from "jsdom";
import "../../tests/unit_tests/test_chrome_stubs.js";
import "../../lib/utils.js";
import "../../lib/settings.js";
import * as completionEngines from "../../background_scripts/completion_engines.js";
import * as page from "../../pages/completion_engines_page.js";

context("completion engines page", () => {
  setup(async () => {
    const html = await Deno.readTextFile("pages/completion_engines_page.html");

    const w = new jsdom.JSDOM(html).window;
    // TODO(philc): Change these to stub, and improve how this works.
    globalThis.window = w;
    globalThis.document = w.document;
    globalThis.MouseEvent = w.MouseEvent;
  });

  teardown(() => {
    globalThis.window = undefined;
    globalThis.document = undefined;
    globalThis.MouseEvent = undefined;
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

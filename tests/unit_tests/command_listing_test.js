import { assert, context, setup, should, stub, teardown } from "../vendor/shoulda.js";
import * as shoulda from "../vendor/shoulda.js";
import * as jsdom from "jsdom";
import "../../tests/unit_tests/test_chrome_stubs.js";
import "../../lib/utils.js";
import "../../lib/utils.js";
import "../../lib/settings.js";
import "../../background_scripts/all_commands.js";
import "../../background_scripts/completion.js";
import * as commandListing from "../../pages/command_listing.js";

context("command listing", () => {
  setup(async () => {
    const html = await Deno.readTextFile("pages/command_listing.html");

    const w = new jsdom.JSDOM(html).window;
    // TODO(philc): Change these to stub, and improve how this works.
    globalThis.window = w;
    globalThis.document = w.document;
    globalThis.MouseEvent = w.MouseEvent;

    await Settings.onLoaded();
    stub(chrome.storage.session, "get", async (key) => {
      if (key == "helpPageData") {
        const data = {
          "reload": {
            "": ["a"],
            "hard": ["b"],
          },
        };
        return { helpPageData: data };
      }
    });
  });

  teardown(() => {
    globalThis.window = undefined;
    globalThis.document = undefined;
  });

  should("have a section in the html for every group", async () => {
    // This is to prevent editing errors, where a new command group is added, and we forget to add a
    // corresponding group to the command listing.
    await commandListing.populatePage();
    const groups = Array.from(new Set(allCommands.map((c) => c.group))).sort();
    const groupsInPage = Array.from(globalThis.document.querySelectorAll("h2[data-group]"))
      .map((e) => e.dataset.group)
      .sort();
    assert.equal(groups, groupsInPage);
  });

  should("have one entry per command", async () => {
    await commandListing.populatePage();
    const rows = globalThis.document.querySelectorAll(".command");
    assert.equal(allCommands.length, rows.length);
  });
});

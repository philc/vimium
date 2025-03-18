import { assert, context, setup, should, stub, teardown } from "../vendor/shoulda.js";
import * as shoulda from "../vendor/shoulda.js";
import * as jsdom from "jsdom";
import "../../tests/unit_tests/test_chrome_stubs.js";
import "../../background_scripts/completion.js";
import { HelpDialog } from "../../pages/help_dialog.js";

context("help dialog", () => {
  setup(async () => {
    const html = await Deno.readTextFile("pages/help_dialog.html");
    const w = new jsdom.JSDOM(html).window;
    // TODO(philc): Change these to stub, and improve how this works.
    globalThis.window = w;
    globalThis.document = w.document;
    globalThis.MouseEvent = w.MouseEvent;

    await Settings.onLoaded();
    stub(chrome.storage.session, "get", async (key) => {
      if (key == "helpPageData") {
        const data = {
          "pageNavigation": [
            {
              keys: ["a"],
              advanced: false,
              description: "example-description",
              options: "example-options",
            },
          ],
        };
        return { helpPageData: data };
      }
    });

  });

  teardown(() => {
    globalThis.window = undefined;
    globalThis.document = undefined;
  });

  should("have a section in the help dialog for every group", async () => {
    // This test is to prevent code editing errors, where a command is added but doesn't have a
    // corresponding group in the help dialog.
    HelpDialog.init();
    await HelpDialog.show({ showAllCommandDetails: false });
    const groups = Array.from(new Set(allCommands.map((c) => c.group))).sort();
    const groupsInDialog = Array.from(HelpDialog.dialogElement.querySelectorAll(".commands"))
      .map((e) => e.dataset.group)
      .sort();
    assert.equal(groups, groupsInDialog);
  });
});

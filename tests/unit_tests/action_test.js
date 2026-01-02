import * as testHelper from "./test_helper.js";
import "../../tests/unit_tests/test_chrome_stubs.js";
import { ActionPage } from "../../pages/action.js";
import { ExclusionRulesEditor } from "../../pages/exclusion_rules_editor.js";

context("ActionPage", () => {
  setup(async () => {
    await testHelper.jsdomStub("pages/action.html");
    await Settings.onLoaded();
  });

  const setupTest = async (rules) => {
    const tab = { id: 1, url: "https://www.example.com/foo" };
    stub(chrome.tabs, "query", () => Promise.resolve([tab]));
    stub(chrome.tabs, "sendMessage", () => Promise.resolve());

    stub(Settings, "get", (key) => key === "exclusionRules" ? rules : []);

    stub(ExclusionRulesEditor, "init", () => {});
    stub(ExclusionRulesEditor, "setForm", () => {});
    stub(ExclusionRulesEditor, "getRules", () => rules);
    stub(ExclusionRulesEditor, "addEventListener", () => {});

    await ActionPage.init();
  };

  should("display 'Some' when some keys are excluded", async () => {
    const rules = [{ pattern: "https://www.example.com/*", passKeys: "a" }];
    await setupTest(rules);
    const caption = document.getElementById("howManyEnabled");
    assert.equal("Some", caption.textContent);
  });

  should("display 'No' when all keys are excluded", async () => {
    const rules = [{ pattern: "https://www.example.com/*", passKeys: "" }];
    await setupTest(rules);
    const caption = document.getElementById("howManyEnabled");
    assert.equal("No", caption.textContent);
  });

  should("display 'All' when no keys are excluded", async () => {
    const rules = [];
    await setupTest(rules);
    const caption = document.getElementById("howManyEnabled");
    assert.equal("All", caption.textContent);
  });
});

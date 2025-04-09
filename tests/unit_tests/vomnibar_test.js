import * as testHelper from "./test_helper.js";
import "../../tests/unit_tests/test_chrome_stubs.js";

import { Suggestion } from "../../background_scripts/completion.js";
import "../../background_scripts/completion.js";
import { Vomnibar } from "../../pages/vomnibar_page.js";

function newKeyEvent(properties) {
  return Object.assign(
    {
      type: "keydown",
      key: "a",
      ctrlKey: false,
      shiftKey: false,
      altKey: false,
      metaKey: false,
      stopImmediatePropagation: function () {},
      preventDefault: function () {},
    },
    properties,
  );
}

context("vomnibar", () => {
  setup(async () => {
    await testHelper.jsdomStub("pages/vomnibar_page.html");
    stub(chrome.runtime, "sendMessage", async (message) => {
      if (message.handler == "filterCompletions") {
        return [];
      }
    });
  });

  should("hide when escape is pressed", async () => {
    const instance = new Vomnibar();
    await instance.activate();
    const ui = instance.vomnibarUI;
    ui.setQuery("www.example.com");
    // Here we assert that the dialog has been reset when esc is pressed, which happens as part of
    // hiding the dialog. It would be better to check more directly that the dialog was hidden, but
    // jacking into the channels for this are not worthwhile for this test.
    await ui.onKeyEvent(newKeyEvent({ key: "Escape" }));
    assert.equal("", ui.input.value);
  });

  should("edit a completion's URL when ctrl-enter is pressed", async () => {
    stub(chrome.runtime, "sendMessage", async (message) => {
      if (message.handler == "filterCompletions") {
        const s = new Suggestion({ url: "http://hello.com" });
        return [s];
      }
    });
    const instance = new Vomnibar();
    await instance.activate();
    const ui = instance.vomnibarUI;
    await ui.onKeyEvent(newKeyEvent({ type: "keydown", key: "up" }));
    // TODO(philc): Why does this need to be lowercase enter?
    await ui.onKeyEvent(newKeyEvent({ type: "keypress", ctrlKey: true, key: "enter" }));
    assert.equal("http://hello.com", ui.input.value);
  });

  should("open a URL-like query when enter is pressed", async () => {
    const instance = new Vomnibar();
    await instance.activate();
    const ui = instance.vomnibarUI;
    ui.setQuery("www.example.com");
    let handler = null;
    let url = null;
    stub(chrome.runtime, "sendMessage", async (message) => {
      handler = message.handler;
      url = message.url;
    });
    await ui.onKeyEvent(newKeyEvent({ type: "keypress", key: "Enter" }));
    assert.equal("openUrlInCurrentTab", handler);
    assert.equal("www.example.com", url);
  });

  should("search for a non-URL query when enter is pressed", async () => {
    const instance = new Vomnibar();
    await instance.activate();
    const ui = instance.vomnibarUI;
    ui.setQuery("example");
    let handler = null;
    let query = null;
    stub(chrome.runtime, "sendMessage", async (message) => {
      handler = message.handler;
      query = message.query;
    });
    await ui.onKeyEvent(newKeyEvent({ type: "keypress", key: "Enter" }));
    ui.onHidden();
    assert.equal("launchSearchQuery", handler);
    assert.equal("example", query);
  });

  // This test covers #4396.
  should("not treat javascript keywords as user-defined search engines", async () => {
    const instance = new Vomnibar();
    await instance.activate();
    const ui = instance.vomnibarUI;
    ui.setQuery("constructor "); // "constructor" is a built-in JS property
    ui.onInput();
    // The query should not be treated as a user search engine.
    assert.equal("constructor ", ui.input.value);
  });
});

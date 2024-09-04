import { assert, context, setup, should, stub } from "../vendor/shoulda.js";
import * as shoulda from "../vendor/shoulda.js";
import "../../lib/chrome_api_stubs.js";
import { Vomnibar } from "../../pages/vomnibar.js";

window.shoulda = shoulda;

const keyEvent = {
  type: "keydown",
  key: "a",
  ctrlKey: false,
  shiftKey: false,
  altKey: false,
  metaKey: false,
  stopImmediatePropagation: function () {},
  preventDefault: function () {},
};

context("vomnibar", () => {
  setup(() => {
    stub(chrome.runtime, "sendMessage", async (message) => {
      if (message.handler == "filterCompletions") {
        return [];
      }
    });
  });

  should("hide when escape is pressed", async () => {
    let wasHidden = false;
    const instance = new Vomnibar();
    await instance.activate();
    const ui = instance.vomnibarUI;
    stub(UIComponentServer, "postMessage", (message) => {
      wasHidden = message == "hide";
    });
    await ui.onKeyEvent(Object.assign(keyEvent, { key: "Escape" }));
    assert.equal(true, wasHidden);
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
    await ui.onKeyEvent(Object.assign(keyEvent, { type: "keypress", key: "Enter" }));
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
    await ui.onKeyEvent(Object.assign(keyEvent, { type: "keypress", key: "Enter" }));
    ui.onHidden();
    assert.equal("launchSearchQuery", handler);
    assert.equal("example", query);
  });
});

import "./test_helper.js";
import * as jsdom from "jsdom";
import "../../lib/keyboard_utils.js";
import "../../lib/dom_utils.js";
import "../../lib/rect.js";
import "../../lib/handler_stack.js";
import "../../lib/settings.js";
import "../../lib/find_mode_history.js";
import "../../content_scripts/mode.js";
import "../../content_scripts/mode_find.js";

// Builds a jsdom document from the given body HTML and stubs the globals that mode_find.js's DOM
// traversal (getAllTextNodes) depends on.
function stubDom(bodyHtml) {
  const w = new jsdom.JSDOM(
    `<!DOCTYPE html><html><head>
      <style>.contents { display: contents; }</style>
     </head><body>${bodyHtml}</body></html>`,
  ).window;

  // jsdom 26 does not implement Element.checkVisibility(), so we provide an approximation that
  // matches the browser behavior we care about: `display: contents` and `display: none` elements
  // generate no box and are reported as not visible.
  w.Element.prototype.checkVisibility = function () {
    const display = w.getComputedStyle(this).display;
    return display !== "none" && display !== "contents";
  };

  stub(globalThis, "window", w);
  stub(globalThis, "document", w.document);
  stub(globalThis, "Node", w.Node);
  stub(globalThis, "getComputedStyle", (el) => w.getComputedStyle(el));
  stub(globalThis, "getSelection", () => ({ rangeCount: 0 }));
  return w;
}

context("find mode text node traversal", () => {
  setup(async () => {
    await Settings.onLoaded();
  });

  teardown(async () => {
    await Settings.clear();
  });

  should("find text inside an element with an inline display:contents style", () => {
    stubDom(`<div style="display: contents"><p>the quick brown fox</p></div>`);
    FindMode.updateQuery("brown");
    assert.equal(1, FindMode.query.matchCount);
  });

  should("find text inside an element given display:contents via a CSS class", () => {
    // Regression test for find mode failing on pages like ChatGPT, where conversation content is
    // wrapped in elements that receive `display: contents` from a Tailwind `.contents` class rather
    // than an inline style attribute. checkVisibility() returns false for such elements, and the
    // previous fix (e304d0a2) only inspected node.style.display (the inline style attribute), so the
    // traversal bailed out and the wrapped text nodes were never searched.
    stubDom(`<div class="contents"><p>the quick brown fox</p></div>`);
    FindMode.updateQuery("brown");
    assert.equal(1, FindMode.query.matchCount);
  });

  should("find text inside nested elements given display:contents via a CSS class", () => {
    stubDom(
      `<div class="contents"><div class="contents"><span>hello world</span></div></div>`,
    );
    FindMode.updateQuery("world");
    assert.equal(1, FindMode.query.matchCount);
  });
});

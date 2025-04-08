import * as shoulda from "../vendor/shoulda.js";
import * as jsdom from "jsdom";
import "./test_chrome_stubs.js";
import "../../lib/utils.js";

const shouldaSubset = {
  assert: shoulda.assert,
  context: shoulda.context,
  ensureCalled: shoulda.ensureCalled,
  setup: shoulda.setup,
  should: shoulda.should,
  shoulda: shoulda,
  stub: shoulda.stub,
  returns: shoulda.returns,
  teardown: shoulda.teardown,
};

globalThis.isUnitTests = true;

// Attach shoulda's functions, like setup, context, should, to the global namespace.
Object.assign(globalThis, shouldaSubset);

export async function jsdomStub(htmlFile) {
  const html = await Deno.readTextFile(htmlFile);
  const w = new jsdom.JSDOM(html).window;
  stub(globalThis, "window", w);
  stub(globalThis, "document", w.document);
  stub(globalThis, "MouseEvent", w.MouseEvent);
  stub(globalThis, "MutationObserver", w.MutationObserver);
  // We might not need to stub HTMLElement once we resolve the TODO on DomUtils.createElement
  stub(globalThis, "HTMLElement", w.HTMLElement);
}

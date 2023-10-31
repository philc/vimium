import * as shoulda from "../vendor/shoulda.js";
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
Object.assign(window, shouldaSubset);

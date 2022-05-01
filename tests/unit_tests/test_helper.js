import * as shoulda from "../vendor/shoulda.js";
import "../../lib/utils.js";
import "./test_chrome_stubs.js";

const shouldaSubset = {
  assert: shoulda.assert,
  context: shoulda.context,
  ensureCalled: shoulda.ensureCalled,
  setup: shoulda.setup,
  should: shoulda.should,
  shoulda: shoulda,
  stub: shoulda.stub,
  returns: shoulda.returns,
  tearDown: shoulda.tearDown,
};

// Attach shoulda's functions, like setup, context, should, to the global namespace.
Object.assign(window, shouldaSubset);

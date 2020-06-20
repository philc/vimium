shoulda = require("../vendor/shoulda.js");

// Attach shoulda's functions, like setup, context, should, to the global namespace.
Object.assign(global, shoulda);

// In a nodejs environment, stub out some essential DOM properties which are required before any of our code
// can be loaded.
if (typeof(window) == "undefined")
  require("./test_chrome_stubs.js")

require("../../lib/utils.js");

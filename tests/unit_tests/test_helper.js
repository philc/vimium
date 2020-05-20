require("../shoulda.js/shoulda.js");

// In a nodejs environment, stub out some essential DOM properties which are required before any of our code
// can be loaded.
if (typeof(window) == "undefined")
  require("./test_chrome_stubs.js")

require("../../lib/utils.js");

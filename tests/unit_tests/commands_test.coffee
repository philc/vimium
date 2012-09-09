require "./test_helper.js"
{Commands} = require "../../background_scripts/commands.js"

context "Key mappings",
  should "lowercase keys correctly", ->
    assert.equal (Commands.normalizeKey '<c-a>'), '<c-a>'
    assert.equal (Commands.normalizeKey '<C-a>'), '<c-a>'
    assert.equal (Commands.normalizeKey '<C-A>'), '<c-A>'
    assert.equal (Commands.normalizeKey '<F12>'), '<f12>'
    assert.equal (Commands.normalizeKey '<C-F12>'), '<c-f12>'

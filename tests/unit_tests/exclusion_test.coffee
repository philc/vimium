
require "./test_helper.js"
extend global, require "./test_chrome_stubs.js"

# FIXME:
# Would like to do:
# extend(global, require "../../background_scripts/marks.js")
# But it looks like marks.coffee has never been included in a test before!
# Temporary fix...
root.Marks =
  create: () -> true
  goto:
    bind: () -> true

extend(global, require "../../lib/utils.js")
Utils.getCurrentVersion = -> '1.44'
extend(global,require "../../lib/settings.js")
extend(global,require "../../lib/clipboard.js")
extend(global, require "../../background_scripts/bg_utils.js")
extend(global, require "../../background_scripts/exclusions.js")
extend(global, require "../../background_scripts/commands.js")
extend(global, require "../../background_scripts/main.js")

isEnabledForUrl = (request) ->
  Exclusions.isEnabledForUrl request.url

# These tests cover only the most basic aspects of excluded URLs and passKeys.
#
context "Excluded URLs and pass keys",

  setup ->
    Settings.set "exclusionRules",
      [
        { pattern: "http*://mail.google.com/*", passKeys: "" }
        { pattern: "http*://www.facebook.com/*", passKeys: "abab" }
        { pattern: "http*://www.facebook.com/*", passKeys: "cdcd" }
        { pattern: "http*://www.bbc.com/*", passKeys: "" }
        { pattern: "http*://www.bbc.com/*", passKeys: "ab" }
        { pattern: "http*://www.example.com/*", passKeys: "a bb c bba a" }
        { pattern: "http*://www.duplicate.com/*", passKeys: "ace" }
        { pattern: "http*://www.duplicate.com/*", passKeys: "bdf" }
      ]
    Exclusions.postUpdateHook()

  should "be disabled for excluded sites", ->
    rule = isEnabledForUrl({ url: 'http://mail.google.com/calendar/page' })
    assert.isFalse rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "be disabled for excluded sites, one exclusion", ->
    rule = isEnabledForUrl({ url: 'http://www.bbc.com/calendar/page' })
    assert.isFalse rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "be enabled, but with pass keys", ->
    rule = isEnabledForUrl({ url: 'https://www.facebook.com/something' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'abcd'

  should "be enabled", ->
    rule = isEnabledForUrl({ url: 'http://www.twitter.com/pages' })
    assert.isTrue rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "handle spaces and duplicates in passkeys", ->
    rule = isEnabledForUrl({ url: 'http://www.example.com/pages' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal "abc", rule.passKeys

  should "handle multiple passkeys rules", ->
    rule = isEnabledForUrl({ url: 'http://www.duplicate.com/pages' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal "abcdef", rule.passKeys

  should "be enabled for malformed regular expressions", ->
    Exclusions.postUpdateHook [ { pattern: "http*://www.bad-regexp.com/*[a-", passKeys: "" } ]
    rule = isEnabledForUrl({ url: 'http://www.bad-regexp.com/pages' })
    assert.isTrue rule.isEnabledForUrl

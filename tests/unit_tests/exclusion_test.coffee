
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
extend(global,require "../../background_scripts/sync.js")
extend(global,require "../../background_scripts/settings.js")
Sync.init()
extend(global, require "../../background_scripts/exclusions.js")
extend(global, require "../../background_scripts/commands.js")
extend(global, require "../../background_scripts/main.js")

dummyTab =
  tab:
    incognito: false

# These tests cover only the most basic aspects of excluded URLs and passKeys.
#
context "Excluded URLs and pass keys",

  setup ->
    Exclusions.postUpdateHook(
      [
        { pattern: "http*://mail.google.com/*", passKeys: "" }
        { pattern: "http*://www.facebook.com/*", passKeys: "abab" }
        { pattern: "http*://www.facebook.com/*", passKeys: "cdcd" }
        { pattern: "http*://www.bbc.com/*", passKeys: "" }
        { pattern: "http*://www.bbc.com/*", passKeys: "ab" }
      ])

  should "be disabled for excluded sites", ->
    rule = isEnabledForUrl({ url: 'http://mail.google.com/calendar/page' }, dummyTab)
    assert.isFalse rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "be disabled for excluded sites, one exclusion", ->
    rule = isEnabledForUrl({ url: 'http://www.bbc.com/calendar/page' }, dummyTab)
    assert.isFalse rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "be enabled, but with pass keys", ->
    rule = isEnabledForUrl({ url: 'https://www.facebook.com/something' }, dummyTab)
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'abcd'

  should "be enabled", ->
    rule = isEnabledForUrl({ url: 'http://www.twitter.com/pages' }, dummyTab)
    assert.isTrue rule.isEnabledForUrl
    assert.isFalse rule.passKeys


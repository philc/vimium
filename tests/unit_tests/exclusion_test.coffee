
require "./test_helper.js"
require "./test_chrome_stubs.js"

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
extend(global, require "../../background_scripts/link_hint_oracle.js")
extend(global, require "../../background_scripts/main.js")

# These tests cover only the most basic aspects of excluded URLs and passKeys.
#
context "Excluded URLs and pass keys",

  # These tests have no setup, they use the default values from settings.coffee.

  should "be disabled for excluded sites", ->
    rule = isEnabledForUrl({ url: 'http://www.google.com/calendar/page' })
    assert.isFalse rule.isEnableForUrl
    assert.isFalse rule.passKeys

  should "be enabled, but with pass keys", ->
    rule = isEnabledForUrl({ url: 'https://www.facebook.com/something' })
    assert.isTrue rule.isEnabledForUrl
    assert.isFalse rule.passKeys
    addExclusionRule("http*://www.facebook.com/*","oO")
    rule = isEnabledForUrl({ url: 'https://www.facebook.com/something' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'oO'

  should "be enabled", ->
    rule = isEnabledForUrl({ url: 'http://www.twitter.com/pages' })
    assert.isTrue rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "add a new excluded URL", ->
    rule = isEnabledForUrl({ url: 'http://www.example.com/page' })
    assert.isTrue rule.isEnabledForUrl
    addExclusionRule("http://www.example.com*")
    rule = isEnabledForUrl({ url: 'http://www.example.com/page' })
    assert.isFalse rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "add a new excluded URL with passkeys", ->
    rule = isEnabledForUrl({ url: 'http://www.anotherexample.com/page' })
    assert.isTrue rule.isEnabledForUrl
    addExclusionRule("http://www.anotherexample.com/*","jk")
    rule = isEnabledForUrl({ url: 'http://www.anotherexample.com/page' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'jk'

  should "update an existing excluded URL with passkeys", ->
    rule = isEnabledForUrl({ url: 'http://mail.google.com/page' })
    assert.isFalse rule.isEnabledForUrl
    assert.isFalse rule.passKeys
    addExclusionRule("http*://mail.google.com/*","jknp")
    rule = isEnabledForUrl({ url: 'http://mail.google.com/page' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'jknp'


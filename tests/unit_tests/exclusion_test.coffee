
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
extend(global, require "../../background_scripts/commands.js")
extend(global, require "../../background_scripts/main.js")

# These tests cover only the most basic aspects of excluded URLs and passKeys.
#
context "Excluded URLs and pass keys",
  setup ->
    Settings.set 'excludedUrls', 'http://mail.google.com/*\nhttp://www.facebook.com/* jk'

  should "be disabled for excluded sites", ->
    rule = isEnabledForUrl({ url: 'http://mail.google.com/u/0/inbox' })
    assert.isFalse rule.isEnableForUrl
    assert.isTrue rule.matchingUrl

  should "be enabled, but with pass keys", ->
    rule = isEnabledForUrl({ url: 'http://www.facebook.com/pages' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'jk'
    assert.isTrue rule.matchingUrl

  should "be enabled", ->
    rule = isEnabledForUrl({ url: 'http://www.twitter.com/pages' })
    assert.isTrue rule.isEnabledForUrl
    assert.isFalse rule.passKeys

  should "add a new excluded URL", ->
    rule = isEnabledForUrl({ url: 'http://www.example.com/page' })
    assert.isTrue rule.isEnabledForUrl
    addExcludedUrl("http://www.example.com*")
    rule = isEnabledForUrl({ url: 'http://www.example.com/page' })
    assert.isFalse rule.isEnabledForUrl
    assert.isFalse rule.passKeys
    assert.isTrue rule.matchingUrl

  should "add a new excluded URL with passkeys", ->
    rule = isEnabledForUrl({ url: 'http://www.example.com/page' })
    assert.isTrue rule.isEnabledForUrl
    addExcludedUrl("http://www.example.com/* jk")
    rule = isEnabledForUrl({ url: 'http://www.example.com/page' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'jk'
    assert.isTrue rule.matchingUrl

  should "update an existing excluded URL with passkeys", ->
    rule = isEnabledForUrl({ url: 'http://www.facebook.com/page' })
    assert.isTrue rule.isEnabledForUrl
    addExcludedUrl("http://www.facebook.com/* jknp")
    rule = isEnabledForUrl({ url: 'http://www.facebook.com/page' })
    assert.isTrue rule.isEnabledForUrl
    assert.equal rule.passKeys, 'jknp'
    assert.isTrue rule.matchingUrl


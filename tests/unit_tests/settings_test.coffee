require "./test_helper.js"
require "./test_chrome_stubs.js"

extend(global, require "../../lib/utils.js")
Utils.getCurrentVersion = -> '1.44'
global.localStorage = {}
extend(global,require "../../background_scripts/sync.js")
extend(global,require "../../background_scripts/settings.js")
Sync.init()

context "settings",

  setup ->
    stub global, 'localStorage', {}

  should "all settings stored in localStorage must be JSONified strings", ->
    Settings.set 'dummy', ""
    assert.equal localStorage.dummy, '""'

  should "obtain defaults if no key is stored", ->
    assert.isFalse Settings.has 'scrollStepSize'
    assert.equal Settings.get('scrollStepSize'), 60

  should "store values", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20

  should "not store values equal to the default", ->
    Settings.set 'scrollStepSize', 20
    assert.isTrue Settings.has 'scrollStepSize'
    Settings.set 'scrollStepSize', 60
    assert.isFalse Settings.has 'scrollStepSize'

  should "revert to defaults if no key is stored", ->
    Settings.set 'scrollStepSize', 20
    Settings.clear 'scrollStepSize'
    assert.equal Settings.get('scrollStepSize'), 60

  should "remote changes take effect locally, non-default value", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    Sync.listener { scrollStepSize: { newValue: "40" } }
    assert.equal Settings.get('scrollStepSize'), 40

  should "remote changes take effect locally, default value", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    Sync.listener { scrollStepSize: { newValue: "60" } }
    assert.isFalse Settings.has 'scrollStepSize'

  should "remote changes are propagated, non-default value", ->
    # Prime Sync.
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    # Set a bogus value in localStorage, bypassing Settings and Sync.
    localStorage['scrollStepSize'] = JSON.stringify(10)
    assert.equal Settings.get('scrollStepSize'), 10
    # Pull Sync's version of scrollStepSize, this should reset it to the correct value (20).
    Sync.pull()
    assert.equal Settings.get('scrollStepSize'), 20

  should "remote changes are propagated, default value", ->
    # Prime Sync with a default value.
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(60) }
    assert.isFalse Settings.has 'scrollStepSize'
    # Set a bogus value in localStorage, bypassing Settings and Sync.
    localStorage['scrollStepSize'] = JSON.stringify(10)
    assert.equal Settings.get('scrollStepSize'), 10
    # Pull Sync's version of scrollStepSize, this should delete scrollStepSize in localStorage, because it's a default value.
    Sync.pull()
    assert.isFalse Settings.has 'scrollStepSize'

  should "remote setting cleared", ->
    # Prime localStorage.
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    # Prime Sync with a non-default value.
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(40) }
    chrome.storage.sync.remove 'scrollStepSize'
    assert.isFalse Settings.has 'scrollStepSize'

  should "trigger a postUpdateHook", ->
    message = "Hello World"
    # Install a bogus update hook for an existing setting.
    Settings.postUpdateHooks['scrollStepSize'] = (value) -> Sync.message = value
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(message) }
    # Was the update hook triggered?
    assert.equal message, Sync.message

  should "sync a key which is not a setting", ->
    # There is nothing to test, here.  It's purpose is just to ensure that, should additional settings be
    # added in future, then the Sync won't cause unexpected crashes.
    chrome.storage.sync.set { notASetting: JSON.stringify("notAUsefullValue") }

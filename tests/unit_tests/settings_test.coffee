require "./test_helper.js"
extend global, require "./test_chrome_stubs.js"

extend(global, require "../../lib/utils.js")
Utils.getCurrentVersion = -> '1.44'
Utils.isBackgroundPage = -> true
Utils.isExtensionPage = -> true
global.localStorage = {}
extend(global,require "../../lib/settings.js")
extend(global,require "../../pages/options.js")

context "settings",

  setup ->
    stub global, 'localStorage', {}
    Settings.cache = global.localStorage # Point the settings cache to the new localStorage object.
    Settings.postUpdateHooks = {} # Avoid running update hooks which include calls to outside of settings.

  should "save settings in localStorage as JSONified strings", ->
    Settings.set 'dummy', ""
    assert.equal localStorage.dummy, '""'

  should "obtain defaults if no key is stored", ->
    assert.isFalse Settings.has 'scrollStepSize'
    assert.equal Settings.get('scrollStepSize'), 60

  should "store values", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20

  should "revert to defaults if no key is stored", ->
    Settings.set 'scrollStepSize', 20
    Settings.clear 'scrollStepSize'
    assert.equal Settings.get('scrollStepSize'), 60

context "synced settings",

  setup ->
    stub global, 'localStorage', {}
    Settings.cache = global.localStorage # Point the settings cache to the new localStorage object.
    Settings.postUpdateHooks = {} # Avoid running update hooks which include calls to outside of settings.

  should "propagate non-default value via synced storage listener", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    Settings.propagateChangesFromChromeStorage { scrollStepSize: { newValue: "40" } }
    assert.equal Settings.get('scrollStepSize'), 40

  should "propagate default value via synced storage listener", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    Settings.propagateChangesFromChromeStorage { scrollStepSize: { newValue: "60" } }
    assert.equal Settings.get('scrollStepSize'), 60

  should "propagate non-default values from synced storage", ->
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(20) }
    assert.equal Settings.get('scrollStepSize'), 20

  should "propagate default values from synced storage", ->
    Settings.set 'scrollStepSize', 20
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(60) }
    assert.equal Settings.get('scrollStepSize'), 60

  should "clear a setting from synced storage", ->
    Settings.set 'scrollStepSize', 20
    chrome.storage.sync.remove 'scrollStepSize'
    assert.equal Settings.get('scrollStepSize'), 60

  should "trigger a postUpdateHook", ->
    message = "Hello World"
    receivedMessage = ""
    Settings.postUpdateHooks['scrollStepSize'] = (value) -> receivedMessage = value
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(message) }
    assert.equal message, receivedMessage

  should "sync a key which is not a known setting (without crashing)", ->
    chrome.storage.sync.set { notASetting: JSON.stringify("notAUsefullValue") }

context "default valuess",

  should "have a default value for every option", ->
    for own key of Options
      assert.isTrue key of Settings.defaults


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

  should "save settings in localStorage as JSONified strings", ->
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

  should "propagate non-default value via synced storage listener", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    Sync.handleStorageUpdate { scrollStepSize: { newValue: "40" } }
    assert.equal Settings.get('scrollStepSize'), 40

  should "propagate default value via synced storage listener", ->
    Settings.set 'scrollStepSize', 20
    assert.equal Settings.get('scrollStepSize'), 20
    Sync.handleStorageUpdate { scrollStepSize: { newValue: "60" } }
    assert.isFalse Settings.has 'scrollStepSize'

  should "propagate non-default values from synced storage", ->
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(20) }
    Sync.fetchAsync()
    assert.equal Settings.get('scrollStepSize'), 20

  should "propagate default values from synced storage", ->
    Settings.set 'scrollStepSize', 20
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(60) }
    Sync.fetchAsync()
    assert.isFalse Settings.has 'scrollStepSize'

  should "clear a setting from synced storage", ->
    Settings.set 'scrollStepSize', 20
    chrome.storage.sync.remove 'scrollStepSize'
    assert.isFalse Settings.has 'scrollStepSize'

  should "trigger a postUpdateHook", ->
    message = "Hello World"
    Settings.postUpdateHooks['scrollStepSize'] = (value) -> Sync.message = value
    chrome.storage.sync.set { scrollStepSize: JSON.stringify(message) }
    assert.equal message, Sync.message

  should "set search engines, retrieve them correctly and check that it has been parsed correctly", ->
    searchEngines = "foo: bar?q=%s\n# comment\nbaz: qux?q=%s"
    parsedSearchEngines = {"foo": "bar?q=%s", "baz": "qux?q=%s"}
    Settings.set 'searchEngines', searchEngines
    assert.equal(searchEngines, Settings.get('searchEngines'))
    result = Settings.getSearchEngines()
    assert.isTrue(parsedSearchEngines["foo"] == result["foo"] &&
      parsedSearchEngines["baz"] == result["baz"] && Object.keys(result).length == 2)

  should "sync a key which is not a known setting (without crashing)", ->
    chrome.storage.sync.set { notASetting: JSON.stringify("notAUsefullValue") }

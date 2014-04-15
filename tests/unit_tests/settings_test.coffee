require "./test_helper.js"

extend(global, require "../../lib/utils.js")
Utils.getCurrentVersion = -> '1.44'
global.localStorage = {}
{Settings} = require "../../background_scripts/settings.js"

context "settings",

  setup ->
    stub global, 'localStorage', {}

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

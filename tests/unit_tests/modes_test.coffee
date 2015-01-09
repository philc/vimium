require "./test_helper.js"
extend(global, require "../../content_scripts/modes.js")

context "Mode constructor",
  should "Register new modes on constructor object", ->
    testMode1 = new Mode "test1"
    testMode2 = new Mode "test2"
    testMode3 = new Mode "test3"

    assert.equal testMode1, Mode.modes.test1
    assert.equal testMode2, Mode.modes.test2
    assert.equal testMode3, Mode.modes.test3

  should "Replace mode with the same name, deactivate old mode", ->
    testMode1 = new Mode "test",1
    stub testMode1, "deactivate", ensureCalled testMode1.deactivate
    assert.equal testMode1, Mode.modes.test

    testMode2 = new Mode "test",2
    assert.equal testMode2, Mode.modes.test

  should "Report correct active status", ->
    testMode = new Mode()

    assert.equal true, testMode.isActive()
    testMode.deactivate()
    assert.equal false, testMode.isActive()
    testMode.activate()
    assert.equal true, testMode.isActive()

  context "Child modes",
    should "", ->

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

  should "Replace mode with the same name, destroy replaced mode", ->
    testMode1 = new Mode "test",1
    stub testMode1, "destructor", ensureCalled testMode1.destructor
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
    should "Register a child mode from the parent", ->
      class TestParentMode extends Mode
        constructor: (name, childName) ->
          super name
          childMode = new Mode childName, {parent: this}

      testModeParent = new TestParentMode "testParent", "testChild"

      assert.isTrue testModeParent.modes.testChild instanceof Mode

    should "Register a child mode via options", ->
      testModeParent = new Mode "testParent"
      testModeChild = new Mode "testChild", {parent: testModeParent}

      assert.equal testModeParent.modes.testChild, testModeChild

    should "Register a child mode via Mode.setMode", ->
      testModeParent = new Mode "testParent"
      testModeChild = new Mode "testChild", {noParent: true}

      assert.equal testModeChild, (Mode.setMode "testParent.testChild", testModeChild)
      assert.equal testModeChild, testModeParent.modes.testChild

    should "Retrieve a child mode via Mode.getMode", ->
      testModeParent = new Mode "testParent"
      testModeChild1 = new Mode "testChild", {parent: testModeParent}
      testModeChild2 = new Mode "testChild", {parent: testModeChild1}

      assert.equal (Mode.getMode "testParent.testChild"), testModeChild1
      assert.equal (Mode.getMode "testParent.testChild.testChild"), testModeChild2

    should "Retrieve a child mode via parent.getMode", ->
      testModeParent = new Mode "testParent"
      testModeChild1 = new Mode "testChild", {parent: testModeParent}
      testModeChild2 = new Mode "testChild", {parent: testModeChild1}

      assert.equal (testModeParent.getMode "testChild"), testModeChild1
      assert.equal (testModeParent.getMode "testChild.testChild"), testModeChild2
      assert.equal (testModeChild1.getMode "testChild"), testModeChild2

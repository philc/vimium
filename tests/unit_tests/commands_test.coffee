require "./test_helper.js"
extend global, require "./test_chrome_stubs.js"
extend global, require "../../background_scripts/command_list.js"
{Commands} = require "../../background_scripts/commands.js"

context "Key mappings",
  should "lowercase keys correctly", ->
    assert.equal (Commands.normalizeKey '<c-a>'), '<c-a>'
    assert.equal (Commands.normalizeKey '<C-a>'), '<c-a>'
    assert.equal (Commands.normalizeKey '<C-A>'), '<c-A>'
    assert.equal (Commands.normalizeKey '<F12>'), '<f12>'
    assert.equal (Commands.normalizeKey '<C-F12>'), '<c-f12>'

context "Validate commands and options",
  should "have a description for each command group", ->
    # TODO(smblott) For this and each following test, is there a way to structure the tests such that the name
    # of the offending command appears in the output, if the test fails?
    for group, commands of commandLists
      assert.equal "string", typeof groupDescriptions[group]

  should "have a name for each command", ->
    for group, commands of commandLists
      for command in commands
        assert.equal "string", typeof command.name

  should "have a description for each command", ->
    for group, commands of commandLists
      for command in commands
        assert.equal "string", typeof command.description

  should "have a valid context for each command", ->
    for group, commands of commandLists
      for command in commands
        contextIndex = ["frame", "background"].indexOf command.context
        assert.isTrue(contextIndex != -1)

  should "have a valid value for repeat for each command", ->
    for group, commands of commandLists
      for command in commands
        repeatIndex = ["normal", "pass_to_function", "none"].indexOf command.repeat
        assert.isTrue(repeatIndex != -1)

  should "not have both repeat=none and repeatLimit", ->
    for group, commands of commandLists
      for command in commands
        assert.isFalse(command.repeat == "none" and "repeatLimit" of command)

  should "have valid commands for each default key mapping", ->
    count = Object.keys(Commands.keyToCommandRegistry).length
    assert.isTrue (0 < count)
    for key, command of Commands.keyToCommandRegistry
      assert.equal 'object', typeof command
      assert.isTrue Commands.availableCommands[command.name]

# TODO (smblott) More tests:
# - Ensure each background command has an implmentation in BackgroundCommands
# - Ensure each foreground command has an implmentation in vimium_frontent.coffee

root.chrome =
  session:
    MAX_SESSION_RESULTS: 25

require "./test_helper.js"
{Commands} = require "../../background_scripts/commands.js"

context "Key mappings",
  should "lowercase keys correctly", ->
    assert.equal (Commands.normalizeKey '<c-a>'), '<c-a>'
    assert.equal (Commands.normalizeKey '<C-a>'), '<c-a>'
    assert.equal (Commands.normalizeKey '<C-A>'), '<c-A>'
    assert.equal (Commands.normalizeKey '<F12>'), '<f12>'
    assert.equal (Commands.normalizeKey '<C-F12>'), '<c-f12>'

context "Validate commands and options",
  should "have either noRepeat or repeatLimit, but not both", ->
    for command, options of Commands.availableCommands
      assert.isTrue not (options.noRepeat and options.repeatLimit)

  should "have a description for each command", ->
    for command, options of Commands.availableCommands
      assert.equal 'string', typeof options.description

  should "have valid commands for each command in each command group", ->
    for group, commands of Commands.commandGroups
      for command in commands
        assert.equal 'string', typeof command
        assert.isTrue Commands.availableCommands[command]

  should "have valid commands for each advanced command", ->
    for command in Commands.advancedCommands
      assert.equal 'string', typeof command
      assert.isTrue Commands.availableCommands[command]

  should "have each advanced command listed in a command group", ->
    allCommands = [].concat.apply [], (commands for group, commands of Commands.commandGroups)
    for command in Commands.advancedCommands
      assert.isTrue 0 <= allCommands.indexOf command

  should "have valid commands for each default key mapping", ->
    count = Object.keys(Commands.keyToCommandRegistry).length
    assert.isTrue (0 < count)
    for key, command of Commands.keyToCommandRegistry
      assert.equal 'object', typeof command
      assert.isTrue Commands.availableCommands[command.command]

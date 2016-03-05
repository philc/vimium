require "./test_helper.js"
extend global, require "./test_chrome_stubs.js"
global.Settings = {postUpdateHooks: {}, get: (-> ""), set: ->}
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
    # TODO(smblott) For this and each following test, is there a way to structure the tests such that the name
    # of the offending command appears in the output, if the test fails?
    for own command, options of Commands.availableCommands
      assert.isTrue not (options.noRepeat and options.repeatLimit)

  should "describe each command", ->
    for own command, options of Commands.availableCommands
      assert.equal 'string', typeof options.description

  should "define each command in each command group", ->
    for own group, commands of Commands.commandGroups
      for command in commands
        assert.equal 'string', typeof command
        assert.isTrue Commands.availableCommands[command]

  should "have valid commands for each advanced command", ->
    for command in Commands.advancedCommands
      assert.equal 'string', typeof command
      assert.isTrue Commands.availableCommands[command]

  should "have valid commands for each default key mapping", ->
    count = Object.keys(Commands.keyToCommandRegistry).length
    assert.isTrue (0 < count)
    for own key, command of Commands.keyToCommandRegistry
      assert.equal 'object', typeof command
      assert.isTrue Commands.availableCommands[command.command]

context "Validate advanced commands",
  setup ->
    @allCommands = [].concat.apply [], (commands for own group, commands of Commands.commandGroups)

  should "include each advanced command in a command group", ->
    for command in Commands.advancedCommands
      assert.isTrue 0 <= @allCommands.indexOf command

# TODO (smblott) More tests:
# - Ensure each background command has an implmentation in BackgroundCommands
# - Ensure each foreground command has an implmentation in vimium_frontent.coffee

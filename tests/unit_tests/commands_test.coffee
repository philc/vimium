require "./test_helper.js"
extend global, require "./test_chrome_stubs.js"
global.Settings = {postUpdateHooks: {}, get: (-> ""), set: ->}
{Commands} = require "../../background_scripts/commands.js"

context "Key mappings",
  setup ->
    @testKeySequence = (key, expectedKeyText, expectedKeyLength) ->
      keySequence = Commands.parseKeySequence key
      assert.equal expectedKeyText, keySequence.join "/"
      assert.equal expectedKeyLength, keySequence.length

  should "lowercase keys correctly", ->
    @testKeySequence "a", "a", 1
    @testKeySequence "A", "A", 1
    @testKeySequence "ab", "a/b", 2

  should "parse keys with modifiers", ->
    @testKeySequence "<c-a>", "<c-a>", 1
    @testKeySequence "<c-A>", "<c-A>", 1
    @testKeySequence "<c-a><a-b>", "<c-a>/<a-b>", 2
    @testKeySequence "<m-a>", "<m-a>", 1

  should "normalize with modifiers", ->
    # Modifiers should be in alphabetical order.
    @testKeySequence "<m-c-a-A>", "<a-c-m-A>", 1

  should "parse and normalize named keys", ->
    @testKeySequence "<space>", "<space>", 1
    @testKeySequence "<Space>", "<space>", 1
    @testKeySequence "<C-Space>", "<c-space>", 1
    @testKeySequence "<f12>", "<f12>", 1
    @testKeySequence "<F12>", "<f12>", 1

  should "handle angle brackets", ->
    @testKeySequence "<", "<", 1
    @testKeySequence ">", ">", 1

    @testKeySequence "<<", "</<", 2
    @testKeySequence ">>", ">/>", 2

    @testKeySequence "<>", "</>", 2
    @testKeySequence "<>", "</>", 2

    @testKeySequence "<<space>", "</<space>", 2

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

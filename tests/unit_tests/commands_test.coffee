require "./test_helper.js"
extend global, require "./test_chrome_stubs.js"
extend global, require "../../background_scripts/bg_utils.js"
global.Settings = {postUpdateHooks: {}, get: (-> ""), set: ->}
{Commands} = require "../../background_scripts/commands.js"

# Include mode_normal to check that all commands have been implemented.
global.KeyHandlerMode = global.Mode = {}
global.KeyboardUtils = {platform: ""}
extend global, require "../../content_scripts/link_hints.js"
extend global, require "../../content_scripts/marks.js"
extend global, require "../../content_scripts/vomnibar.js"
{NormalModeCommands} = require "../../content_scripts/mode_normal.js"

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

  should "recognise non-alphabetic keys", ->
    @testKeySequence "#", "#", 1
    @testKeySequence ".", ".", 1
    @testKeySequence "##", "#/#", 2
    @testKeySequence "..", "./.", 2

  should "parse keys with modifiers", ->
    @testKeySequence "<c-a>", "<c-a>", 1
    @testKeySequence "<c-A>", "<c-A>", 1
    @testKeySequence "<C-A>", "<c-A>", 1
    @testKeySequence "<c-a><a-b>", "<c-a>/<a-b>", 2
    @testKeySequence "<m-a>", "<m-a>", 1
    @testKeySequence "z<m-a>", "z/<m-a>", 2

  should "normalize with modifiers", ->
    # Modifiers should be in alphabetical order.
    @testKeySequence "<m-c-a-A>", "<a-c-m-A>", 1

  should "parse and normalize named keys", ->
    @testKeySequence "<space>", "<space>", 1
    @testKeySequence "<Space>", "<space>", 1
    @testKeySequence "<C-Space>", "<c-space>", 1
    @testKeySequence "<f12>", "<f12>", 1
    @testKeySequence "<F12>", "<f12>", 1

  should "handle angle brackets which are part of not modifiers", ->
    @testKeySequence "<", "<", 1
    @testKeySequence ">", ">", 1

    @testKeySequence "<<", "</<", 2
    @testKeySequence ">>", ">/>", 2

    @testKeySequence "<>", "</>", 2
    @testKeySequence "<>", "</>", 2

    @testKeySequence "<<space>", "</<space>", 2
    @testKeySequence "<C->>", "<c->>", 1

    @testKeySequence "<a>", "</a/>", 3

  should "negative tests", ->
    # These should not be parsed as modifiers.
    @testKeySequence "<b-a>", "</b/-/a/>", 5
    @testKeySequence "<c-@@>", "</c/-/@/@/>", 6

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

context "Parse commands",
  should "omit whitespace", ->
    assert.equal 0, BgUtils.parseLines("    \n    \n   ").length

  should "omit comments", ->
    assert.equal 0, BgUtils.parseLines(" # comment   \n \" comment   \n   ").length

  should "join lines", ->
    assert.equal 1, BgUtils.parseLines("a\\\nb").length
    assert.equal "ab", BgUtils.parseLines("a\\\nb")[0]

  should "trim lines", ->
    assert.equal 2, BgUtils.parseLines("  a  \n  b").length
    assert.equal "a", BgUtils.parseLines("  a  \n  b")[0]
    assert.equal "b", BgUtils.parseLines("  a  \n  b")[1]

context "Commands implemented",
  (for own command, options of Commands.availableCommands
    do (command, options) ->
      if options.background
        should "#{command} (background command)", ->
          # TODO: Import background_scripts/main.js and expose BackgroundCommands from there.
          # assert.isTrue BackgroundCommands[command]
      else
        should "#{command} (foreground command)", ->
          assert.isTrue NormalModeCommands[command]
  )...

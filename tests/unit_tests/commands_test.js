require("./test_helper.js");
require("../../background_scripts/bg_utils.js");
global.Settings = {postUpdateHooks: {}, get() { return ""; }, set() {}};
require("../../background_scripts/commands.js");

// Include mode_normal to check that all commands have been implemented.
global.KeyboardUtils = {platform: ""};
require("../../content_scripts/mode.js");
require("../../content_scripts/mode_key_handler.js");
require("../../content_scripts/mode_normal.js");
require("../../content_scripts/link_hints.js");
require("../../content_scripts/marks.js");
require("../../content_scripts/vomnibar.js");

context("Key mappings",
  setup(() => {
    this.testKeySequence = (key, expectedKeyText, expectedKeyLength) => {
      const keySequence = Commands.parseKeySequence(key);
      assert.equal(expectedKeyText, keySequence.join("/"));
      assert.equal(expectedKeyLength, keySequence.length);
    };
  }),

  should("lowercase keys correctly", () => {
    this.testKeySequence("a", "a", 1);
    this.testKeySequence("A", "A", 1);
    this.testKeySequence("ab", "a/b", 2);
  }),

  should("recognise non-alphabetic keys", () => {
    this.testKeySequence("#", "#", 1);
    this.testKeySequence(".", ".", 1);
    this.testKeySequence("##", "#/#", 2);
    this.testKeySequence("..", "./.", 2);
  }),

  should("parse keys with modifiers", () => {
    this.testKeySequence("<c-a>", "<c-a>", 1);
    this.testKeySequence("<c-A>", "<c-A>", 1);
    this.testKeySequence("<C-A>", "<c-A>", 1);
    this.testKeySequence("<c-a><a-b>", "<c-a>/<a-b>", 2);
    this.testKeySequence("<m-a>", "<m-a>", 1);
    this.testKeySequence("z<m-a>", "z/<m-a>", 2);
  }),

  should("normalize with modifiers", () => {
    // Modifiers should be in alphabetical order.
    this.testKeySequence("<m-c-a-A>", "<a-c-m-A>", 1);
  }),

  should("parse and normalize named keys", () => {
    this.testKeySequence("<space>", "<space>", 1);
    this.testKeySequence("<Space>", "<space>", 1);
    this.testKeySequence("<C-Space>", "<c-space>", 1);
    this.testKeySequence("<f12>", "<f12>", 1);
    this.testKeySequence("<F12>", "<f12>", 1);
  }),

  should("handle angle brackets which are part of not modifiers", () => {
    this.testKeySequence("<", "<", 1);
    this.testKeySequence(">", ">", 1);

    this.testKeySequence("<<", "</<", 2);
    this.testKeySequence(">>", ">/>", 2);

    this.testKeySequence("<>", "</>", 2);
    this.testKeySequence("<>", "</>", 2);

    this.testKeySequence("<<space>", "</<space>", 2);
    this.testKeySequence("<C->>", "<c->>", 1);

    this.testKeySequence("<a>", "</a/>", 3);
  }),

  should("negative tests", () => {
    // These should not be parsed as modifiers.
    this.testKeySequence("<b-a>", "</b/-/a/>", 5);
    this.testKeySequence("<c-@@>", "</c/-/@/@/>", 6);
  })
);

context("Validate commands and options",
  should("have either noRepeat or repeatLimit, but not both", () => {
    // TODO(smblott) For this and each following test, is there a way to structure the tests such that the name
    // of the offending command appears in the output, if the test fails?
    for (let command of Object.keys(Commands.availableCommands)) {
      const options = Commands.availableCommands[command];
      assert.isTrue(!(options.noRepeat && options.repeatLimit));
    }
  }),

  should("describe each command", () => {
    for (let command of Object.keys(Commands.availableCommands)) {
      const options = Commands.availableCommands[command];
      assert.equal("string", typeof options.description);
    }
  }),

  should("define each command in each command group", () => {
    for (let group of Object.keys(Commands.commandGroups)) {
      const commands = Commands.commandGroups[group];
      for (let command of commands) {
        assert.equal("string", typeof command);
        assert.isTrue(Commands.availableCommands[command]);
      }
    }
  }),

  should("have valid commands for each advanced command", () => {
    for (let command of Commands.advancedCommands) {
      assert.equal("string", typeof command);
      assert.isTrue(Commands.availableCommands[command]);
    }
  }),

  should("have valid commands for each default key mapping", () => {
    const count = Object.keys(Commands.keyToCommandRegistry).length;
    assert.isTrue((0 < count));
    for (let key of Object.keys(Commands.keyToCommandRegistry)) {
      const command = Commands.keyToCommandRegistry[key];
      assert.equal("object", typeof command);
      assert.isTrue(Commands.availableCommands[command.command]);
    }
  })
);

context("Validate advanced commands",
  setup(() => {
    this.allCommands = [];
    for (let _ of Object.keys(Commands.commandGroups)) {
      const commands = Commands.commandGroups[_];
      this.allCommands = this.allCommands.concat(commands);
    }
  }),

  should("include each advanced command in a command group", () => {
    for (let command of Commands.advancedCommands) {
      assert.isTrue(0 <= this.allCommands.indexOf(command));
    }
  })
);

context("Parse commands",
  should("omit whitespace", () => {
    assert.equal(0, BgUtils.parseLines("    \n    \n   ").length);
  }),

  should("omit comments", () => {
    assert.equal(0, BgUtils.parseLines(" # comment   \n \" comment   \n   ").length);
  }),

  should("join lines", () => {
    assert.equal(1, BgUtils.parseLines("a\\\nb").length);
    assert.equal("ab", BgUtils.parseLines("a\\\nb")[0]);
  }),

  should("trim lines", () => {
    assert.equal(2, BgUtils.parseLines("  a  \n  b").length);
    assert.equal("a", BgUtils.parseLines("  a  \n  b")[0]);
    assert.equal("b", BgUtils.parseLines("  a  \n  b")[1]);
  })
);

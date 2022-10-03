import "./test_helper.js";
import "../../background_scripts/bg_utils.js";
import "../../lib/settings.js";
import "../../lib/keyboard_utils.js";
import "../../background_scripts/commands.js";
import "../../content_scripts/mode.js";
import "../../content_scripts/mode_key_handler.js";
// Include mode_normal to check that all commands have been implemented.
import "../../content_scripts/mode_normal.js";
import "../../content_scripts/link_hints.js";
import "../../content_scripts/marks.js";
import "../../content_scripts/vomnibar.js";

context("Key mappings", () => {
  const testKeySequence = (key, expectedKeyText, expectedKeyLength) => {
    const keySequence = Commands.parseKeySequence(key);
    assert.equal(expectedKeyText, keySequence.join("/"));
    assert.equal(expectedKeyLength, keySequence.length);
  };

  should("lowercase keys correctly", () => {
    testKeySequence("a", "a", 1);
    testKeySequence("A", "A", 1);
    testKeySequence("ab", "a/b", 2);
  });

  should("recognise non-alphabetic keys", () => {
    testKeySequence("#", "#", 1);
    testKeySequence(".", ".", 1);
    testKeySequence("##", "#/#", 2);
    testKeySequence("..", "./.", 2);
  });

  should("parse keys with modifiers", () => {
    testKeySequence("<c-a>", "<c-a>", 1);
    testKeySequence("<c-A>", "<c-A>", 1);
    testKeySequence("<C-A>", "<c-A>", 1);
    testKeySequence("<c-a><a-b>", "<c-a>/<a-b>", 2);
    testKeySequence("<m-a>", "<m-a>", 1);
    testKeySequence("z<m-a>", "z/<m-a>", 2);
  });

  should("normalize with modifiers", () => {
    // Modifiers should be in alphabetical order.
    testKeySequence("<m-c-a-A>", "<a-c-m-A>", 1);
  });

  should("parse and normalize named keys", () => {
    testKeySequence("<space>", "<space>", 1);
    testKeySequence("<Space>", "<space>", 1);
    testKeySequence("<C-Space>", "<c-space>", 1);
    testKeySequence("<f12>", "<f12>", 1);
    testKeySequence("<F12>", "<f12>", 1);
  });

  should("handle angle brackets which are part of not modifiers", () => {
    testKeySequence("<", "<", 1);
    testKeySequence(">", ">", 1);

    testKeySequence("<<", "</<", 2);
    testKeySequence(">>", ">/>", 2);

    testKeySequence("<>", "</>", 2);
    testKeySequence("<>", "</>", 2);

    testKeySequence("<<space>", "</<space>", 2);
    testKeySequence("<C->>", "<c->>", 1);

    testKeySequence("<a>", "</a/>", 3);
  });

  should("negative tests", () => {
    // These should not be parsed as modifiers.
    testKeySequence("<b-a>", "</b/-/a/>", 5);
    testKeySequence("<c-@@>", "</c/-/@/@/>", 6);
  });
});


context("Validate commands and options", () => {
  // TODO(smblott) For this and each following test, is there a way to structure the tests such that the name
  // of the offending command appears in the output, if the test fails?
  should("have either noRepeat or repeatLimit, but not both", () => {
    for (let command of Object.keys(Commands.availableCommands)) {
      const options = Commands.availableCommands[command];
      assert.isTrue(!(options.noRepeat && options.repeatLimit));
    }
  });

  should("describe each command", () => {
    for (let command of Object.keys(Commands.availableCommands)) {
      const options = Commands.availableCommands[command];
      assert.equal("string", typeof options.description);
    }
  });

  should("define each command in each command group", () => {
    for (let group of Object.keys(Commands.commandGroups)) {
      const commands = Commands.commandGroups[group];
      for (let command of commands) {
        assert.equal("string", typeof command);
        assert.isTrue(Commands.availableCommands[command]);
      }
    }
  });

  should("have valid commands for each advanced command", () => {
    for (let command of Commands.advancedCommands) {
      assert.equal("string", typeof command);
      assert.isTrue(Commands.availableCommands[command]);
    }
  });

  should("have valid commands for each default key mapping", () => {
    const count = Object.keys(Commands.keyToCommandRegistry).length;
    assert.isTrue((0 < count));
    for (let key of Object.keys(Commands.keyToCommandRegistry)) {
      const command = Commands.keyToCommandRegistry[key];
      assert.equal("object", typeof command);
      assert.isTrue(Commands.availableCommands[command.command]);
    }
  })
});

context("Validate advanced commands", () => {
  should("include each advanced command in a command group", () => {
    let allCommands = Object.keys(Commands.commandGroups).map((k) => Commands.commandGroups[k]).flat(1);
    for (let command of Commands.advancedCommands)
      assert.isTrue(allCommands.includes(command));
  })
});

context("Parse commands", () => {
  should("omit whitespace", () => {
    assert.equal(0, BgUtils.parseLines("    \n    \n   ").length);
  });

  should("omit comments", () => {
    assert.equal(0, BgUtils.parseLines(" # comment   \n \" comment   \n   ").length);
  });

  should("join lines", () => {
    assert.equal(1, BgUtils.parseLines("a\\\nb").length);
    assert.equal("ab", BgUtils.parseLines("a\\\nb")[0]);
  });

  should("trim lines", () => {
    assert.equal(2, BgUtils.parseLines("  a  \n  b").length);
    assert.equal("a", BgUtils.parseLines("  a  \n  b")[0]);
    assert.equal("b", BgUtils.parseLines("  a  \n  b")[1]);
  })
});

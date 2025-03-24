import "./test_helper.js";
import "../../background_scripts/tab_recency.js";
import "../../background_scripts/bg_utils.js";
import "../../background_scripts/all_commands.js";
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

await Commands.init();

context("parseKeySequence", () => {
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

context("parseKeyMappingConfig", () => {
  should("handle map statements", () => {
    const { keyToRegistryEntry } = Commands.parseKeyMappingsConfig("map a scrollDown");
    assert.equal("scrollDown", keyToRegistryEntry["a"]?.command);
  });

  should("ignore mappings for unknown commands", () => {
    assert.equal({}, Commands.parseKeyMappingsConfig("map a unknownCommand").keyToRegistryEntry);
  });

  should("handle mapkey statements", () => {
    const { keyToMappedKey } = Commands.parseKeyMappingsConfig("mapkey a b");
    assert.equal({ "a": "b" }, keyToMappedKey);
  });

  should("handle unmap statements", () => {
    const input = "mapkey a b \n unmap a";
    const { keyToMappedKey } = Commands.parseKeyMappingsConfig(input);
    assert.equal({}, keyToMappedKey);
  });

  should("handle unmapall statements", () => {
    const input = "mapkey a b \n unmapall \n mapkey b c";
    const { keyToMappedKey } = Commands.parseKeyMappingsConfig(input);
    assert.equal({ "b": "c" }, keyToMappedKey);
  });

  should("ignore commands with the wrong number of tokens", () => {
    assert.equal({}, Commands.parseKeyMappingsConfig("mapkey a b c").keyToMappedKey);
    assert.equal({}, Commands.parseKeyMappingsConfig("map a").keyToRegistryEntry);
    assert.equal(
      { "a": "b" },
      Commands.parseKeyMappingsConfig("mapkey a b \n unmap a a").keyToMappedKey,
    );
  });

  should("return validation errors", () => {
    const getErrors = (config) => Commands.parseKeyMappingsConfig(config).validationErrors;
    assert.equal(0, getErrors("map a scrollDown").length);
    // Missing an action (map).
    assert.equal(1, getErrors("a scrollDown").length);
    // Invalid action.
    assert.equal(1, getErrors("invalidAction a scrollDown").length);
    // Unmap allows only 1 argument.
    assert.equal(0, getErrors("unmap a").length);
    assert.equal(1, getErrors("unmap a b").length);
    // Mapkey requires 2 arguments.
    assert.equal(0, getErrors("mapkey a b").length);
    assert.equal(1, getErrors("mapkey a").length);
  });
});

// TODO(philc): Re-enable some version of these sanity check tests.
// context("Validate commands and options", () => {
//   // TODO(smblott) For this and each following test, is there a way to structure the tests such that
//   // the name of the offending command appears in the output, if the test fails?
//   should("have either noRepeat or repeatLimit, but not both", () => {
//     for (const command of Object.keys(Commands.availableCommands)) {
//       const options = Commands.availableCommands[command];
//       assert.isTrue(!(options.noRepeat && options.repeatLimit));
//     }
//   });

//   should("describe each command", () => {
//     for (const command of Object.keys(Commands.availableCommands)) {
//       const options = Commands.availableCommands[command];
//       assert.equal("string", typeof options.description);
//     }
//   });

//   should("define each command in each command group", () => {
//     for (const group of Object.keys(Commands.commandGroups)) {
//       const commands = Commands.commandGroups[group];
//       for (const command of commands) {
//         assert.equal("string", typeof command);
//         assert.isTrue(Commands.availableCommands[command]);
//       }
//     }
//   });

//   should("have valid commands for each default key mapping", () => {
//     const count = Object.keys(Commands.keyToRegistryEntry).length;
//     assert.isTrue(0 < count);
//     for (const key of Object.keys(Commands.keyToRegistryEntry)) {
//       const command = Commands.keyToRegistryEntry[key];
//       assert.equal("object", typeof command);
//       assert.isTrue(Commands.availableCommands[command.command]);
//     }
//   });
// });

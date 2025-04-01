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

context("Validate commands and options data structures", () => {
  should("have either noRepeat or repeatLimit, but not both", () => {
    for (const command of allCommands) {
      const validProperties = !(command.noRepeat && command.repeatLimit);
      if (!validProperties) {
        assert.fail(`${command.name} has incorrect noRepeat and/or repeatLimit config.`);
      }
    }
  });

  should("have required properties", () => {
    for (const command of allCommands) {
      const hasRequired = command.desc.length > 0 && command.group.length > 0;
      if (!hasRequired) {
        assert.fail(`${command.name} is missing required properties.`);
      }
    }
  });

  should("have valid commands for each default key mapping", () => {
    const commandsByName = Utils.keyBy(allCommands, "name");
    for (const [key, commandString] of Object.entries(defaultKeyMappings)) {
      // The comamnd string might be command name + an option string. Ignore the options.
      const name = commandString.split(" ")[0];
      if (commandsByName[name] == null) {
        assert.fail(`The default mapping for ${key} is bound to non-existant command ${name}.`);
      }
    }
  });
});

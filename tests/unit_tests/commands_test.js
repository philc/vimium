import "./test_helper.js";
import "../../lib/settings.js";
import "../../lib/keyboard_utils.js";
import { allCommands } from "../../background_scripts/all_commands.js";
import {
  Commands,
  defaultKeyMappings,
  KeyMappingsParser,
  parseLines,
} from "../../background_scripts/commands.js";
import "../../content_scripts/mode.js";
import "../../content_scripts/mode_key_handler.js";
import "../../content_scripts/marks.js";
import "../../content_scripts/link_hints.js";
import "../../content_scripts/vomnibar.js";
// Include mode_normal to check that all commands have been implemented.
import "../../content_scripts/mode_normal.js";
import "../../content_scripts/link_hints.js";
import "../../content_scripts/marks.js";
import "../../content_scripts/vomnibar.js";

await Commands.init();

context("KeyMappingsParser", () => {
  const getErrors = (config) => KeyMappingsParser.parse(config).validationErrors;

  should("handle map statements", () => {
    const { keyToRegistryEntry } = KeyMappingsParser.parse("map a scrollDown");
    assert.equal("scrollDown", keyToRegistryEntry["a"]?.command);
  });

  should("ignore mappings for unknown commands", () => {
    assert.equal({}, KeyMappingsParser.parse("map a unknownCommand").keyToRegistryEntry);
  });

  should("handle mapkey statements", () => {
    const { keyToMappedKey } = KeyMappingsParser.parse("mapkey a b");
    assert.equal({ "a": "b" }, keyToMappedKey);
  });

  should("handle unmap statements", () => {
    const input = "mapkey a b \n unmap a";
    const { keyToMappedKey } = KeyMappingsParser.parse(input);
    assert.equal({}, keyToMappedKey);
  });

  should("handle unmapall statements", () => {
    const input = "mapkey a b \n unmapall \n mapkey b c";
    const { keyToMappedKey } = KeyMappingsParser.parse(input);
    assert.equal({ "b": "c" }, keyToMappedKey);
  });

  should("ignore commands with the wrong number of tokens", () => {
    assert.equal({}, KeyMappingsParser.parse("mapkey a b c").keyToMappedKey);
    assert.equal({}, KeyMappingsParser.parse("map a").keyToRegistryEntry);
    assert.equal(
      { "a": "b" },
      KeyMappingsParser.parse("mapkey a b \n unmap a a").keyToMappedKey,
    );
  });

  should("parse option values surrounded by quotes", () => {
    const { keyToRegistryEntry } = KeyMappingsParser.parse('map v Vomnibar.activate query="a b"');
    const entry = keyToRegistryEntry["v"];
    assert.equal({ query: "a b" }, entry.options);
  });

  should("parse options using all 3 syntaxes", () => {
    // This test exercises some of the edge cases of the underlying regular expressions.
    const result = KeyMappingsParser.parseCommandOptions('key1  key2="a b=c"  key3=" ');
    assert.equal({ key1: true, key2: "a b=c", key3: '"' }, result);
  });

  should("return parsing validation errors", () => {
    assert.equal(0, getErrors("map a scrollDown").length);
    // Missing an action (e.g. map).
    assert.equal(1, getErrors("a scrollDown").length);
    // Invalid action.
    assert.equal(1, getErrors("invalidAction a scrollDown").length);
    // Map requires at least two arguments
    assert.equal(0, getErrors("map a scrollDown").length);
    assert.equal(1, getErrors("map a").length);
    // Unmap allows only 1 argument.
    assert.equal(0, getErrors("unmap a").length);
    assert.equal(1, getErrors("unmap a b").length);
    // Mapkey requires 2 arguments.
    assert.equal(0, getErrors("mapkey a b").length);
    assert.equal(1, getErrors("mapkey a").length);
    // Reject unknown modifiers.
    assert.equal(0, getErrors("map <a-f> scrollDown").length);
    assert.equal(1, getErrors("map <b-f> scrollDown").length);
  });

  should("reject unknown commands on map statements", () => {
    // Reject unknown commands.
    assert.equal(1, getErrors("map a example-command").length);
  });

  should("reject unknown options on map statements", () => {
    assert.equal(0, getErrors("map j LinkHints.activateMode action=focus").length);
    assert.equal(1, getErrors("map j LinkHints.activateMode unknownOption=a").length);
  });

  should("reject count option on commands with noRepeat=true", () => {
    assert.equal(0, getErrors("map j scrollLeft count=1").length);
    assert.equal(1, getErrors("map j copyCurrentUrl count=1").length);
  });

  should("allow arbitrary URLs as arguments to commands with (any url) as an option", () => {
    assert.equal(0, getErrors("map j createTab http://example.com").length);
    assert.equal(1, getErrors("map j createTab invalid-url").length);
  });

  context("parseLines", () => {
    should("omit whitespace", () => {
      assert.equal(0, parseLines("    \n    \n   ").length);
    });

    should("omit comments", () => {
      assert.equal(0, parseLines(' # comment   \n " comment   \n   ').length);
    });

    should("join lines", () => {
      assert.equal(1, parseLines("a\\\nb").length);
      assert.equal("ab", parseLines("a\\\nb")[0]);
    });

    should("trim lines", () => {
      assert.equal(2, parseLines("  a  \n  b").length);
      assert.equal("a", parseLines("  a  \n  b")[0]);
      assert.equal("b", parseLines("  a  \n  b")[1]);
    });
  });

  context("parseKeySequence", () => {
    const testKeySequence = (key, expectedKeyText, expectedKeyLength) => {
      const keySequence = KeyMappingsParser.parseKeySequence(key);
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
      // This should not be parsed as modifiers.
      testKeySequence("<c-@@>", "</c/-/@/@/>", 6);
    });
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

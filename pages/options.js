import "./all_content_scripts.js";
import { ExclusionRulesEditor } from "./exclusion_rules_editor.js";
import { allCommands } from "../background_scripts/all_commands.js";
import { Commands } from "../background_scripts/commands.js";

const options = {
  filterLinkHints: "boolean",
  waitForEnterForFilteredHints: "boolean",
  hideHud: "boolean",
  keyMappings: "string",
  linkHintCharacters: "string",
  linkHintNumbers: "string",
  newTabUrl: "string",
  nextPatterns: "string",
  previousPatterns: "string",
  regexFindMode: "boolean",
  ignoreKeyboardLayout: "boolean",
  scrollStepSize: "number",
  smoothScroll: "boolean",
  grabBackFocus: "boolean",
  searchEngines: "string",
  settingsVersion: "string", // This is a hidden field.
  userDefinedLinkHintCss: "string",
};

const OptionsPage = {
  async init() {
    await Settings.onLoaded();

    const saveButton = document.querySelector("#save");

    const onUpdated = () => {
      saveButton.disabled = false;
      saveButton.textContent = "Save changes";
    };

    for (const el of document.querySelectorAll("input, textarea")) {
      // We want to immediately enable the save button when a setting is changed, so we want to use
      // the HTML element's "input" event here rather than the "change" event.
      el.addEventListener("input", () => onUpdated());
      el.addEventListener("blur", () => {
        this.showValidationErrors();
      });
    }

    saveButton.addEventListener("click", () => this.saveOptions());

    this.getOptionEl("filterLinkHints").addEventListener(
      "click",
      () => this.maintainLinkHintsView(),
    );

    document.querySelector("#download-backup").addEventListener(
      "mousedown",
      () => this.onDownloadBackupClicked(),
      true,
    );
    document.querySelector("#upload-backup").addEventListener(
      "change",
      () => this.onUploadBackupClicked(),
    );

    for (const el of document.querySelectorAll(".reset-link a")) {
      el.addEventListener("click", (event) => {
        this.resetInputValue(event);
        this.showValidationErrors();
        onUpdated();
      });
    }

    globalThis.onbeforeunload = () => {
      if (!saveButton.disabled) {
        return "You have unsaved changes to options.";
      }
    };

    document.addEventListener("keyup", (event) => {
      const isCtrlEnter = event.ctrlKey && event.keyCode === 13;
      if (isCtrlEnter) {
        this.saveOptions();
      }
    });

    ExclusionRulesEditor.init();
    ExclusionRulesEditor.addEventListener("input", onUpdated);

    const settings = Settings.getSettings();
    this.setFormFromSettings(settings);
  },

  getOptionEl(optionName) {
    return document.querySelector(`*[name="${optionName}"]`);
  },

  // Invoked when the user clicks the "reset" button next to an option's text field.
  resetInputValue(event) {
    const parentDiv = event.target.parentNode.parentNode;
    console.assert(parentDiv?.tagName == "DIV", "Expected parent to be a div", event.target);
    const input = parentDiv.querySelector("input") || parentDiv.querySelector("textarea");
    const optionName = input.name;
    const defaultValue = Settings.defaultOptions[optionName];
    input.value = defaultValue;
    event.preventDefault();
  },

  setFormFromSettings(settings) {
    for (const [optionName, optionType] of Object.entries(options)) {
      const el = this.getOptionEl(optionName);
      const value = settings[optionName];
      switch (optionType) {
        case "boolean":
          el.checked = value;
          break;
        case "number":
          el.value = value;
          break;
        case "string":
          el.value = value;
          break;
        default:
          throw new Error(`Unrecognized option type ${optionType}`);
      }
    }

    ExclusionRulesEditor.setForm(Settings.get("exclusionRules"));

    document.querySelector("#upload-backup").value = "";
    this.maintainLinkHintsView();
  },

  getSettingsFromForm() {
    const settings = {};
    for (const [optionName, optionType] of Object.entries(options)) {
      const el = this.getOptionEl(optionName);
      let value;
      switch (optionType) {
        case "boolean":
          value = el.checked;
          break;
        case "number":
          value = parseFloat(el.value);
          break;
        case "string":
          value = el.value.trim();
          break;
        default:
          throw new Error(`Unrecognized option type ${optionType}`);
      }
      if (value !== null) {
        settings[optionName] = value;
      }
    }
    if (settings["linkHintCharacters"] != null) {
      settings["linkHintCharacters"] = settings["linkHintCharacters"].toLowerCase();
    }
    settings["exclusionRules"] = ExclusionRulesEditor.getRules();
    return settings;
  },

  getValidationErrors() {
    const results = {};
    let text, parsed;

    // keyMappings field.
    text = this.getOptionEl("keyMappings").value.trim();
    parsed = Commands.parseKeyMappingsConfig(text);
    if (parsed.validationErrors.length > 0) {
      results["keyMappings"] = parsed.validationErrors.join("\n");
    }

    // searchEngines field.
    text = this.getOptionEl("searchEngines").value.trim();
    parsed = UserSearchEngines.parseConfig(text);
    if (parsed.validationErrors.length > 0) {
      results["searchEngines"] = parsed.validationErrors.join("\n");
    }

    // linkHintCharacters field.
    text = this.getOptionEl("linkHintCharacters").value.trim();
    if (text != this.removeDuplicateChars(text)) {
      results["linkHintCharacters"] = "This cannot contain duplicate characters.";
    } else if (text.length <= 1) {
      results["linkHintCharacters"] = "This must be at least two characters long.";
    }

    // linkHintNumbers field.
    text = this.getOptionEl("linkHintNumbers").value.trim();
    if (text != this.removeDuplicateChars(text)) {
      results["linkHintNumbers"] = "This cannot contain duplicate characters.";
    } else if (text.length <= 1) {
      results["linkHintNumbers"] = "This must be at least two characters long.";
    }

    return results;
  },

  addValidationMessage(el, message) {
    el.classList.add("validation-error");
    const exampleEl = el.nextElementSibling;
    const messageEl = document.createElement("div");
    messageEl.classList.add("validation-message");
    messageEl.innerText = message;
    exampleEl.after(messageEl);
  },

  // Returns true if there are errors, false otherwise.
  showValidationErrors() {
    // Remove all previous validation errors.
    let els = document.querySelectorAll(".validation-error");
    for (const el of els) {
      el.classList.remove("validation-error");
    }
    els = document.querySelectorAll(".validation-message");
    for (const el of els) {
      el.remove();
    }

    const errors = this.getValidationErrors();
    for (const [optionName, message] of Object.entries(errors)) {
      const el = this.getOptionEl(optionName);
      this.addValidationMessage(el, message);
    }
    // Some options can be hidden in the UI. If they have validation errors, force them to be shown.
    if (errors["linkHintCharacters"]) {
      this.showElement(document.querySelector("#link-hint-characters-container"), true);
    }
    if (errors["linkHintNumbers"]) {
      this.showElement(document.querySelector("#link-hint-numbers-container"), true);
    }
    const hasErrors = Object.keys(errors).length > 0;
    return hasErrors;
  },

  removeDuplicateChars(str) {
    const seen = new Set();
    let result = "";
    for (let char of str) {
      if (!seen.has(char)) {
        result += char;
        seen.add(char);
      }
    }
    return result;
  },

  async saveOptions() {
    const hasErrors = this.showValidationErrors();
    if (hasErrors) {
      // TODO(philc): If no fields with validation errors are in view, scroll one of them into view
      // so it's clear what the issue is.
      return;
    }

    await Settings.setSettings(this.getSettingsFromForm());
    const el = document.querySelector("#save");
    el.disabled = true;
    el.textContent = "Saved";
  },

  showElement(el, visible) {
    el.style.display = visible ? null : "none";
  },

  // Display the UI for link hint numbers vs. characters, depending upon the value of
  // "filterLinkHints".
  maintainLinkHintsView() {
    const errors = this.getValidationErrors();
    const isFilteredLinkhints = this.getOptionEl("filterLinkHints").checked;
    this.showElement(
      document.querySelector("#link-hint-characters-container"),
      !isFilteredLinkhints || errors["linkHintCharacters"],
    );
    this.showElement(
      document.querySelector("#link-hint-numbers-container"),
      isFilteredLinkhints || errors["linkHintNumbers"],
    );
    this.showElement(
      document.querySelector("#wait-for-enter"),
      isFilteredLinkhints,
    );
  },

  onDownloadBackupClicked() {
    const backup = Settings.pruneOutDefaultValues(this.getSettingsFromForm());
    const settingsBlob = new Blob([JSON.stringify(backup, null, 2) + "\n"]);
    document.querySelector("#download-backup").href = URL.createObjectURL(settingsBlob);
  },

  onUploadBackupClicked() {
    if (document.activeElement) {
      document.activeElement.blur();
    }

    const files = event.target.files;
    if (files.length === 1) {
      const file = files[0];
      const reader = new FileReader();
      reader.readAsText(file);
      reader.onload = async () => {
        let backup;
        try {
          backup = JSON.parse(reader.result);
        } catch (error) {
          console.log("parsing error:", error);
          alert("Failed to parse Vimium backup: " + error);
          return;
        }

        await Settings.setSettings(backup);
        this.setFormFromSettings(Settings.getSettings());
        const saveButton = document.querySelector("#save");
        saveButton.disabled = true;
        saveButton.textContent = "Saved";
        alert("Settings have been restored from the backup.");
      };
    }
  },
};

document.addEventListener("DOMContentLoaded", async () => {
  await Settings.onLoaded();
  DomUtils.injectUserCss();
  await Commands.init();
  await OptionsPage.init();
});

// Exported for use by our tests.
globalThis.isVimiumOptionsPage = true;

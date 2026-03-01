import "./all_content_scripts.js";
import { ExclusionRulesEditor } from "./exclusion_rules_editor.js";
import { allCommands } from "../background_scripts/all_commands.js";
import { Commands, KeyMappingsParser } from "../background_scripts/commands.js";
import * as userSearchEngines from "../background_scripts/user_search_engines.js";

const options = {
  filterLinkHints: "boolean",
  grabBackFocus: "boolean",
  hideHud: "boolean",
  hideUpdateNotifications: "boolean",
  ignoreKeyboardLayout: "boolean",
  keyMappings: "string",
  linkHintCharacters: "string",
  linkHintNumbers: "string",
  newTabCustomUrl: "string",
  newTabDestination: "option",
  nextPatterns: "string",
  openVomnibarOnNewTabPage: "boolean",
  previousPatterns: "string",
  regexFindMode: "boolean",
  scrollStepSize: "number",
  searchEngines: "string",
  settingsVersion: "string", // This is a hidden field.
  smoothScroll: "boolean",
  userDefinedLinkHintCss: "string",
  waitForEnterForFilteredHints: "boolean",
};

export async function init() {
  await Settings.onLoaded();

  const shortcutLabel = document.querySelector("#shortcut-to-save-all");
  shortcutLabel.textContent = KeyboardUtils.platform == "Mac" ? "Cmd-Enter" : "Ctrl-Enter";

  const saveButton = document.querySelector("#save");

  const onUpdated = () => {
    maintainNewTabUrlView();
    saveButton.disabled = false;
    saveButton.textContent = "Save changes";
  };

  for (const el of document.querySelectorAll("input, textarea")) {
    // We want to immediately enable the save button when a setting is changed, so we want to use
    // the HTML element's "input" event here rather than the "change" event.
    el.addEventListener("input", () => onUpdated());
    el.addEventListener("blur", () => {
      showValidationErrors();
    });
  }

  saveButton.addEventListener("click", () => saveOptions());

  getOptionEl("filterLinkHints").addEventListener(
    "click",
    () => maintainLinkHintsView(),
  );

  document.querySelector("#download-backup").addEventListener(
    "mousedown",
    () => onDownloadBackupClicked(),
    true,
  );
  document.querySelector("#upload-backup").addEventListener(
    "change",
    () => onUploadBackupClicked(),
  );

  for (const el of document.querySelectorAll(".reset-link a")) {
    el.addEventListener("click", (event) => {
      resetInputValue(event);
      showValidationErrors();
      onUpdated();
    });
  }

  globalThis.onbeforeunload = () => {
    if (!saveButton.disabled) {
      return "You have unsaved changes to options.";
    }
  };

  document.addEventListener("keydown", (event) => {
    // Firefox on Mac doesn't pass ctrl-enter to our page because MacOS Sequoia treats it as a
    // shortcut for right click; typing it shows a context menu. So, we also allow cmd-enter to save
    // all options. Note that ctrl-enter still works on Chrome for some reason.
    const isCtrlEnter = event.ctrlKey && event.keyCode === 13;
    const isCmdEnter = event.metaKey && event.keyCode === 13;
    if (isCtrlEnter || isCmdEnter) {
      saveOptions();
    }
  });

  ExclusionRulesEditor.init();
  ExclusionRulesEditor.addEventListener("input", onUpdated);

  const settings = Settings.getSettings();
  setFormFromSettings(settings);
}

export function getOptionEl(optionName) {
  return document.querySelector(`*[name="${optionName}"]`);
}

// Invoked when the user clicks the "reset" button next to an option's text field.
function resetInputValue(event) {
  const parentDiv = event.target.parentNode.parentNode;
  console.assert(parentDiv?.tagName == "DIV", "Expected parent to be a div", event.target);
  const input = parentDiv.querySelector("input") || parentDiv.querySelector("textarea");
  const optionName = input.name;
  const defaultValue = Settings.defaultOptions[optionName];
  input.value = defaultValue;
  event.preventDefault();
}

function setFormFromSettings(settings) {
  for (const [optionName, optionType] of Object.entries(options)) {
    const el = getOptionEl(optionName);
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
      case "option":
        const optionEl = document.querySelector(`input[name="${optionName}"][value="${value}"]`);
        optionEl.checked = true;
        break;
      default:
        throw new Error(`Unrecognized option type ${optionType}`);
    }
  }

  ExclusionRulesEditor.setForm(settings["exclusionRules"]);

  document.querySelector("#upload-backup").value = "";
  maintainLinkHintsView();
  maintainNewTabUrlView();
}

function getSettingsFromForm() {
  const settings = {};
  for (const [optionName, optionType] of Object.entries(options)) {
    const el = getOptionEl(optionName);
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
      case "option":
        const optionEl = document.querySelector(`input[name="${optionName}"]:checked`);
        value = optionEl.value;
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
}

function getValidationErrors() {
  const results = {};
  let text, parsed;

  // keyMappings field.
  text = getOptionEl("keyMappings").value.trim();
  parsed = KeyMappingsParser.parse(text);
  if (parsed.validationErrors.length > 0) {
    results["keyMappings"] = parsed.validationErrors.join("\n");
  }

  // searchEngines field.
  text = getOptionEl("searchEngines").value.trim();
  parsed = userSearchEngines.parseConfig(text);
  if (parsed.validationErrors.length > 0) {
    results["searchEngines"] = parsed.validationErrors.join("\n");
  }

  // linkHintCharacters field.
  text = getOptionEl("linkHintCharacters").value.trim();
  if (text != removeDuplicateChars(text)) {
    results["linkHintCharacters"] = "This cannot contain duplicate characters.";
  } else if (text.length <= 1) {
    results["linkHintCharacters"] = "This must be at least two characters long.";
  }

  // linkHintNumbers field.
  text = getOptionEl("linkHintNumbers").value.trim();
  if (text != removeDuplicateChars(text)) {
    results["linkHintNumbers"] = "This cannot contain duplicate characters.";
  } else if (text.length <= 1) {
    results["linkHintNumbers"] = "This must be at least two characters long.";
  }

  return results;
}

function addValidationMessage(el, message) {
  el.classList.add("validation-error");
  const exampleEl = el.nextElementSibling;
  const messageEl = document.createElement("div");
  messageEl.classList.add("validation-message");
  messageEl.textContent = message;
  exampleEl.after(messageEl);
}

// Returns true if there are errors, false otherwise.
function showValidationErrors() {
  // Remove all previous validation errors.
  let els = document.querySelectorAll(".validation-error");
  for (const el of els) {
    el.classList.remove("validation-error");
  }
  els = document.querySelectorAll(".validation-message");
  for (const el of els) {
    el.remove();
  }

  const errors = getValidationErrors();
  for (const [optionName, message] of Object.entries(errors)) {
    const el = getOptionEl(optionName);
    addValidationMessage(el, message);
  }
  // Some options can be hidden in the UI. If they have validation errors, force them to be shown.
  if (errors["linkHintCharacters"]) {
    showElement(document.querySelector("#link-hint-characters-container"), true);
  }
  if (errors["linkHintNumbers"]) {
    showElement(document.querySelector("#link-hint-numbers-container"), true);
  }
  const hasErrors = Object.keys(errors).length > 0;
  return hasErrors;
}

function removeDuplicateChars(str) {
  const seen = new Set();
  let result = "";
  for (let char of str) {
    if (!seen.has(char)) {
      result += char;
      seen.add(char);
    }
  }
  return result;
}

export async function saveOptions() {
  const hasErrors = showValidationErrors();
  if (hasErrors) {
    // TODO(philc): If no fields with validation errors are in view, scroll one of them into view
    // so it's clear what the issue is.
    return;
  }

  await Settings.setSettings(getSettingsFromForm());
  const el = document.querySelector("#save");
  el.disabled = true;
  el.textContent = "Saved";
}

function showElement(el, visible) {
  el.style.display = visible ? null : "none";
}

// Hide or show extra form elements depending on which radio button is selected for
// newTabDestination.
function maintainNewTabUrlView() {
  const destination = document.querySelector("[name=newTabDestination]:checked").value;
  showElement(
    document.querySelector("#openVomnibarContainer"),
    destination == Settings.newTabDestinations.vimiumNewTabPage,
  );
  showElement(
    document.querySelector("[name=newTabCustomUrl]"),
    destination == Settings.newTabDestinations.customUrl,
  );
}

// Display the UI for link hint numbers vs. characters, depending upon the value of
// "filterLinkHints".
function maintainLinkHintsView() {
  const errors = getValidationErrors();
  const isFilteredLinkhints = getOptionEl("filterLinkHints").checked;
  showElement(
    document.querySelector("#link-hint-characters-container"),
    !isFilteredLinkhints || errors["linkHintCharacters"],
  );
  showElement(
    document.querySelector("#link-hint-numbers-container"),
    isFilteredLinkhints || errors["linkHintNumbers"],
  );
  showElement(
    document.querySelector("#wait-for-enter"),
    isFilteredLinkhints,
  );
}

export function prepareBackupSettings() {
  const settings = Settings.pruneOutDefaultValues(getSettingsFromForm());
  // Serialize the JSON keys in order, so that they're stable across backups. See #4764.
  const keys = Object.keys(settings).sort();
  const sortedSettings = Object.fromEntries(keys.map((k) => [k, settings[k]]));
  // Don't use an array replacer in JSON.stringify; it filters nested object keys too, which would
  // drop nested fields inside exclusionRules (e.g. `pattern`, `passKeys`). See #4853.
  return JSON.stringify(sortedSettings, null, 2) + "\n";
}

function onDownloadBackupClicked() {
  const settings = prepareBackupSettings();
  const blob = new Blob([settings]);
  document.querySelector("#download-backup").href = URL.createObjectURL(blob);
}

function onUploadBackupClicked() {
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
      setFormFromSettings(Settings.getSettings());
      const saveButton = document.querySelector("#save");
      saveButton.disabled = true;
      saveButton.textContent = "Saved";
      alert("Settings have been restored from the backup.");
    };
  }
}

const testEnv = globalThis.window == null ||
  globalThis.window.location.search.includes("dom_tests=true");
if (!testEnv) {
  document.addEventListener("DOMContentLoaded", async () => {
    await Settings.onLoaded();
    DomUtils.injectUserCss();
    await Commands.init();
    await init();
  });
}

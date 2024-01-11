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
  searchUrl: "string",
  settingsVersion: "string", // This is a hidden field.
  userDefinedLinkHintCss: "string",
};

const OptionsPage = {
  async init() {
    await Settings.onLoaded();

    const saveOptionsEl = document.querySelector("#saveOptions");

    const onUpdated = () => {
      saveOptionsEl.disabled = false;
      saveOptionsEl.textContent = "Save changes";
    };

    for (const el of document.querySelectorAll("input, textarea")) {
      // We want to immediately enable the save button when a setting is changed, so we want to use
      // the HTML element's "input" event here rather than the "change" event.
      el.addEventListener("input", () => onUpdated());
    }

    saveOptionsEl.addEventListener("click", () => this.saveOptions());
    document.querySelector("#showCommands").addEventListener(
      "click",
      () => HelpDialog.toggle({ showAllCommandDetails: true }),
    );

    document.querySelector("#filterLinkHints").addEventListener(
      "click",
      () => this.maintainLinkHintsView(),
    );

    document.querySelector("#downloadBackup").addEventListener(
      "mousedown",
      () => this.onDownloadBackupClicked(),
      true,
    );
    document.querySelector("#uploadBackup").addEventListener(
      "change",
      () => this.onUploadBackupClicked(),
    );

    for (const el of document.querySelectorAll(".reset-link a")) {
      el.addEventListener("click", (event) => {
        this.resetInputValue(event);
        onUpdated();
      });
    }

    window.onbeforeunload = () => {
      if (!saveOptionsEl.disabled) {
        return "You have unsaved changes to options.";
      }
    };

    document.addEventListener("keyup", (event) => {
      const isCtrlEnter = event.ctrlKey && event.keyCode === 13;
      if (isCtrlEnter) {
        document.activeElement?.blur?.();
        this.saveOptions();
      }
    });

    ExclusionRulesEditor.init();
    ExclusionRulesEditor.addEventListener("input", onUpdated);

    const settings = Settings.getSettings();
    this.setFormFromSettings(settings);
  },

  // Invoked when the user clicks the "reset" button next to an option's text field.
  resetInputValue(event) {
    const parent = event.target.closest("tr");
    const input = parent.querySelector("input") || parent.querySelector("textarea");
    const optionName = input.id;
    const defaultValue = Settings.defaultOptions[optionName];
    input.value = defaultValue;
    event.preventDefault();
  },

  setFormFromSettings(settings) {
    for (const [optionName, optionType] of Object.entries(options)) {
      const el = document.getElementById(optionName);
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

    document.querySelector("#uploadBackup").value = "";
    this.maintainLinkHintsView();
  },

  getSettingsFromForm() {
    const settings = {};
    for (const [optionName, optionType] of Object.entries(options)) {
      const el = document.getElementById(optionName);
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

  async saveOptions() {
    await Settings.setSettings(this.getSettingsFromForm());
    const el = document.querySelector("#saveOptions");
    el.disabled = true;
    el.textContent = "Saved";
  },

  // Display the UI for link hint numbers vs. characters, depending upon the value of
  // "filterLinkHints".
  maintainLinkHintsView() {
    const show = (el, visible) => el.style.display = visible ? "table-row" : "none";
    const isFilteredLinkhints = document.querySelector("#filterLinkHints").checked;
    show(document.querySelector("#linkHintCharactersContainer"), !isFilteredLinkhints);
    show(document.querySelector("#linkHintNumbersContainer"), isFilteredLinkhints);
    show(document.querySelector("#waitForEnterForFilteredHintsContainer"), isFilteredLinkhints);
  },

  onDownloadBackupClicked() {
    const backup = Settings.pruneOutDefaultValues(this.getSettingsFromForm());
    const settingsBlob = new Blob([JSON.stringify(backup, null, 2) + "\n"]);
    document.querySelector("#downloadBackup").href = URL.createObjectURL(settingsBlob);
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
        const saveOptionsEl = document.querySelector("#saveOptions");
        saveOptionsEl.disabled = true;
        saveOptionsEl.textContent = "Saved";
        alert("Settings have been restored from the backup.");
      };
    }
  },
};

document.addEventListener("DOMContentLoaded", async () => {
  await Settings.onLoaded();
  DomUtils.injectUserCss();
  await OptionsPage.init();
});

// Exported for use by our tests.
window.isVimiumOptionsPage = true;

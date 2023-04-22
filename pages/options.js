// TODO(philc): manifest v3 - custom styles needs to be fixed.

// Mixin-functions for enabling a class to dispatch methods.
const EventDispatcher = {
  addEventListener: (eventName, listener) => {
    this.events = this.events || [];
    this.events[eventName] = this.events[eventName] || [];
    this.events[eventName].push(listener);
  },

  dispatchEvent: (eventName) => {
    this.events = this.events || [];
    for (const listener of this.events[eventName] || []) {
      listener();
    }
  },

  removeEventListener: (eventName, listener) => {
    const events = this.events || {};
    const listeners = events[eventName] || [];
    if (listeners.length > 0) {
      events[eventName] = listeners.filter((l) => l != listener);
    }
  },
};

// The table-editor used for exclusion rules.
const ExclusionRulesEditor = {
  init() {
    document.querySelector("#exclusionAddButton").addEventListener("click", () => {
      this.addRow();
      this.dispatchEvent("change");
    });
  },

  // - exclusionRules: the value obtained from settings, with the shape [{pattern, passKeys}].
  setForm(exclusionRules = []) {
    const rulesTable = document.querySelector("#exclusionRules");
    // Remove any previous rows.
    const existingRuleEls = rulesTable.querySelectorAll(".rule");
    for (const el of existingRuleEls) el.remove();

    const rowTemplate = document.querySelector("#exclusionRuleTemplate").content;
    for (const rule of exclusionRules) {
      this.addRow(rule.pattern, rule.passKeys);
    }
  },

  // `pattern` and `passKeys` are optional.
  addRow(pattern, passKeys) {
    const rulesTable = document.querySelector("#exclusionRules");
    const rowTemplate = document.querySelector("#exclusionRuleTemplate").content;
    const rowEl = rowTemplate.cloneNode(true);

    const patternEl = rowEl.querySelector("[name=pattern]");
    patternEl.value = pattern ?? "";
    patternEl.addEventListener("input", () => this.dispatchEvent("change"));

    const keysEl = rowEl.querySelector("[name=passKeys]");
    keysEl.value = passKeys ?? "";
    keysEl.addEventListener("input", () => this.dispatchEvent("change"));

    rowEl.querySelector(".remove").addEventListener("click", (e) => {
      e.target.closest("tr").remove();
      this.dispatchEvent("change");
    });
    rulesTable.appendChild(rowEl);
  },

  // Returns an array of rules, which can be stored in Settings.
  getRules() {
    const rows = Array.from(document.querySelectorAll("#exclusionRules tr.rule"));
    const rules = rows
      .map((el) => {
        return {
          // The ordering of these keys should match the order in defaultOptions in Settings.js.
          passKeys: el.querySelector("[name=passKeys]").value.trim(),
          pattern: el.querySelector("[name=pattern]").value.trim(),
        };
      })
      // Exclude blank patterns.
      .filter((rule) => rule.pattern);
    return rules;
  },
};

Object.assign(ExclusionRulesEditor, EventDispatcher);

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
  userDefinedLinkHintCss: "string",
};

const OptionsPage = {
  init: async () => {
    await Settings.onLoaded();

    const saveOptionsEl = document.querySelector("#saveOptions");

    const onUpdated = () => {
      saveOptionsEl.removeAttribute("disabled");
      saveOptionsEl.textContent = "Save Changes";
    };

    for (const el of document.querySelectorAll("input, textarea")) {
      el.addEventListener("change", () => onUpdated());
    }

    saveOptionsEl.addEventListener("click", () => OptionsPage.saveOptions());
    document.querySelector("#showCommands").addEventListener(
      "click",
      () => HelpDialog.toggle({ showAllCommandDetails: true }),
    );

    document.querySelector("#filterLinkHints").addEventListener(
      "click",
      () => OptionsPage.maintainLinkHintsView(),
    );

    document.querySelector("#downloadBackup").addEventListener(
      "mousedown",
      () => OptionsPage.onDownloadBackupClicked(),
      true,
    );
    document.querySelector("#uploadBackup").addEventListener(
      "change",
      () => OptionsPage.onUploadBackupClicked(),
    );

    window.onbeforeunload = () => {
      if (!saveOptionsEl.disabled) {
        return "You have unsaved changes to options.";
      }
    };

    document.addEventListener("keyup", (event) => {
      if (event.ctrlKey && (event.keyCode === 13)) {
        if (document && document.activeElement && document.activeElement.blur) {
          document.activeElement.blur();
          OptionsPage.saveOptions();
        }
      }
    });

    ExclusionRulesEditor.init();
    ExclusionRulesEditor.addEventListener("change", onUpdated);

    const settings = Settings.getSettings();
    OptionsPage.setFormFromSettings(settings);
  },

  setFormFromSettings: (settings) => {
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
          throw `Unrecognized option type ${optionType}`;
      }
    }

    ExclusionRulesEditor.setForm(Settings.get("exclusionRules"));

    document.querySelector("#uploadBackup").value = "";
    OptionsPage.maintainLinkHintsView();
  },

  getSettingsFromForm: () => {
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
          throw `Unrecognized option type ${optionType}`;
      }
      if (value !== null && value !== "") {
        settings[optionName] = value;
      }
    }
    if (settings["linkHintCharacters"] != null) {
      settings["linkHintCharacters"] = settings["linkHintCharacters"].toLowerCase();
    }
    settings["exclusionRules"] = ExclusionRulesEditor.getRules();
    return settings;
  },

  saveOptions: () => {
    Settings.setSettings(OptionsPage.getSettingsFromForm());
    const el = document.querySelector("#saveOptions");
    el.disabled = true;
    el.textContent = "Saved";
  },

  // Display the UI for link hint numbers vs. characters, depending upon the value of
  // "filterLinkHints".
  maintainLinkHintsView: () => {
    const show = (el, visible) => el.style.display = visible ? "table-row" : "none";
    const isFilteredLinkhints = document.querySelector("#filterLinkHints").checked;
    show(document.querySelector("#linkHintCharactersContainer"), !isFilteredLinkhints);
    show(document.querySelector("#linkHintNumbersContainer"), isFilteredLinkhints);
    show(document.querySelector("#waitForEnterForFilteredHintsContainer"), isFilteredLinkhints);
  },

  onDownloadBackupClicked: () => {
    let backup = OptionsPage.getSettingsFromForm();
    backup = Settings.pruneOutDefaultValues(backup);
    // TODO(philc):
    // backup.settingsVersion = settings["settingsVersion"];
    const settingsBlob = new Blob([JSON.stringify(backup, null, 2) + "\n"]);
    document.querySelector("#downloadBackup").href = URL.createObjectURL(settingsBlob);
  },

  onUploadBackupClicked: () => {
    if (document.activeElement) {
      document.activeElement.blur();
    }

    // TODO(philc): This settings version needs to be handled as part of Settings.set.
    let restoreSettingsVersion = null;
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
        OptionsPage.setFormFromSettings(Settings.getSettings());
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

  // TODO(philc): manifest v3
  // DomUtils.injectUserCss(); // Manually inject custom user styles.

  switch (location.pathname) {
    case "/pages/options.html":
      await OptionsPage.init();
      break;
    // TODO(philc): manifest v3: Fix the options page
    // case "/pages/popup.html":
    //   initPopupPage();
    //   break;
  }
});

// Exported for use by our tests.
window.isVimiumOptionsPage = true;

// TODO(philc): Exclusions logic needs to be fixed, and custom styles.
const $ = (id) => document.getElementById(id);
// TODO(philc): manifest v3
const bgExclusions = null; // chrome.extension.getBackgroundPage().Exclusions;

// TODO(philc): Remove once we revisit exclusion rules
class Option {
  constructor(field, onUpdated) {
    this.field = field;
    // this.onUpdated = onUpdated;
    this.element = $(this.field);
    // this.element.addEventListener("change", this.onUpdated);
    // Option.all.push(this);
  }

  // Fetch a setting from localStorage, remember the @previous value and populate the DOM element.
  // Return the fetched value.
  fetch() {
    // // return; // TODO(philc): manifest v3
    // this.populateElement(this.previous = bgSettings[this.field]);
    // return this.previous;
  }

  // Write this option's new value back to localStorage, if necessary.
  save() {
    // const value = this.readValueFromElement();
    // if (JSON.stringify(value) !== JSON.stringify(this.previous)) {
    //   bgSettings[this.field] = this.previous = value;
    // }
  }

  // Static method.
  // static saveOptions() {
  //   Option.all.map((option) => option.save());
  //   Settings2.set(bgSettings);
  //   this.onSaveCallbacks.map((callback) => callback());
  // }
}

class ExclusionRulesOption extends Option {
  constructor(...args) {
    super(...Array.from(args || []));
    $("exclusionAddButton").addEventListener("click", (event) => {
      this.addRule();
    });
  }

  // Add a new rule, focus its pattern, scroll it into view, and return the newly-added element. On
  // the options page, there is no current URL, so there is no initial pattern. This is the default.
  // On the popup page (see ExclusionRulesOnPopupOption), the pattern is pre-populated based on the
  // current tab's URL.
  addRule(pattern) {
    if (pattern == null) {
      pattern = "";
    }
    const element = this.appendRule({ pattern, passKeys: "" });
    this.getPattern(element).focus();
    const exclusionScrollBox = $("exclusionScrollBox");
    exclusionScrollBox.scrollTop = exclusionScrollBox.scrollHeight;
    this.onUpdated();
    return element;
  }

  populateElement(rules) {
    // For the case of restoring a backup, we first have to remove existing rules.
    const exclusionRules = $("exclusionRules");
    while (exclusionRules.rows[1]) exclusionRules.deleteRow(1);
    for (let rule of rules) {
      this.appendRule(rule);
    }
  }

  // Append a row for a new rule.  Return the newly-added element.
  appendRule(rule) {
    let element;
    const content = document.querySelector("#exclusionRuleTemplate").content;
    const row = document.importNode(content, true);

    for (let field of ["passKeys", "pattern"]) {
      element = row.querySelector(`.${field}`);
      element.value = rule[field];
      for (let event of ["input", "change"]) {
        element.addEventListener(event, this.onUpdated);
      }
    }

    this.getRemoveButton(row).addEventListener("click", (event) => {
      rule = event.target.parentNode.parentNode;
      rule.parentNode.removeChild(rule);
      this.onUpdated();
    });

    this.element.appendChild(row);
    return this.element.children[this.element.children.length - 1];
  }

  readValueFromElement() {
    const rules = Array.from(this.element.getElementsByClassName("exclusionRuleTemplateInstance"))
      .map((element) => ({
        // The ordering of these keys should match the order in defaultOptins in Settings.js
        passKeys: this.getPassKeys(element).value.trim(),
        pattern: this.getPattern(element).value.trim(),
      }));
    return rules.filter((rule) => rule.pattern);
  }

  // Accessors for the three main sub-elements of an "exclusionRuleTemplateInstance".
  getPattern(element) {
    return element.querySelector(".pattern");
  }
  getPassKeys(element) {
    return element.querySelector(".passKeys");
  }
  getRemoveButton(element) {
    return element.querySelector(".exclusionRemoveButton");
  }
}

// ExclusionRulesOnPopupOption is ExclusionRulesOption, extended with some UI tweeks suitable for
// use in the page popup. This also differs from ExclusionRulesOption in that, on the page popup,
// there is always a URL (@url) associated with the current tab.
class ExclusionRulesOnPopupOption extends ExclusionRulesOption {
  constructor(url, ...args) {
    super(...Array.from(args || []));
    this.url = url;
  }

  addRule() {
    const element = super.addRule(this.generateDefaultPattern());
    this.activatePatternWatcher(element);
    // ExclusionRulesOption.addRule()/super() has focused the pattern. Here, focus the passKeys
    // instead; because, in the popup, we already have a pattern, so the user is more likely to edit
    // the passKeys.
    this.getPassKeys(element).focus();
    // Return element (for consistency with ExclusionRulesOption.addRule()).
    return element;
  }

  populateElement(rules) {
    let element;
    super.populateElement(rules);
    const elements = this.element.getElementsByClassName("exclusionRuleTemplateInstance");
    for (element of Array.from(elements)) {
      this.activatePatternWatcher(element);
    }

    let haveMatch = false;
    for (element of Array.from(elements)) {
      const pattern = this.getPattern(element).value.trim();
      if (0 <= this.url.search(bgExclusions.RegexpCache.get(pattern))) {
        haveMatch = true;
        this.getPassKeys(element).focus();
      } else {
        element.style.display = "none";
      }
    }
    if (!haveMatch) {
      return this.addRule();
    }
  }

  // Provide visual feedback (make it red) when a pattern does not match the current tab's URL.
  activatePatternWatcher(element) {
    const patternElement = element.children[0].firstChild;
    patternElement.addEventListener("keyup", () => {
      // TODO(philc): manifest v3
      // if (this.url.match(bgExclusions.RegexpCache.get(patternElement.value))) {
      //   patternElement.title = patternElement.style.color = "";
      // } else {
      //   patternElement.style.color = "red";
      //   patternElement.title = "Red text means that the pattern does not\nmatch the current URL.";
      // }
    });
  }

  // Generate a default exclusion-rule pattern from a URL. This is then used to pre-populate the
  // pattern on the page popup.
  generateDefaultPattern() {
    if (/^https?:\/\/./.test(this.url)) {
      // The common use case is to disable Vimium at the domain level.
      // Generate "https?://www.example.com/*" from "http://www.example.com/path/to/page.html".
      // Note: IPV6 host addresses will contain "[" and "]" (which must be escaped).
      const hostname = this.url.split("/", 3).slice(1).join("/").replace("[", "\\[").replace(
        "]",
        "\\]",
      );
      return "https?:/" + hostname + "/*";
    } else if (/^[a-z]{3,}:\/\/./.test(this.url)) {
      // Anything else which seems to be a URL.
      return this.url.split("/", 3).join("/") + "/*";
    } else {
      return this.url + "*";
    }
  }
}

const options = {
  // TODO(philc):
  // exclusionRules: ExclusionRulesOption,
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
    await Settings2.load();

    const onUpdated = function () {
      $("saveOptions").removeAttribute("disabled");
      $("saveOptions").textContent = "Save Changes";
    };

    for (const el of document.querySelectorAll("input, textarea")) {
      el.addEventListener("change", () => onUpdated());
    }

    $("saveOptions").addEventListener("click", () => OptionsPage.saveOptions());
    $("showCommands").addEventListener(
      "click",
      () => HelpDialog.toggle({ showAllCommandDetails: true }),
    );
    $("filterLinkHints").addEventListener("click", () => OptionsPage.maintainLinkHintsView());

    $("downloadBackup").addEventListener(
      "mousedown",
      () => OptionsPage.onDownloadBackupClicked(),
      true,
    );
    $("uploadBackup").addEventListener("change", () => OptionsPage.onUploadBackupClicked());

    window.onbeforeunload = () => {
      if (!$("saveOptions").disabled) {
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

    const settings = await Settings2.getSettings();
    OptionsPage.setFormFromSettings(settings);
  },

  setFormFromSettings: (settings) => {
    for (const [optionName, optionType] of Object.entries(options)) {
      const el = $(optionName);
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
    $("uploadBackup").value = "";
    OptionsPage.maintainLinkHintsView();
  },

  getSettingsFromForm: () => {
    const settings = {};
    for (const [optionName, optionType] of Object.entries(options)) {
      const el = $(optionName);
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
    return settings;
  },

  saveOptions: () => {
    Settings2.setSettings(OptionsPage.getSettingsFromForm());
    $("saveOptions").disabled = true;
    $("saveOptions").textContent = "Saved";
  },

  // Display either "linkHintNumbers" or "linkHintCharacters", depending upon the value of
  // "filterLinkHints".
  maintainLinkHintsView: () => {
    const hide = (el) => el.style.display = "none";
    const show = (el) => el.style.display = "table-row";
    if ($("filterLinkHints").checked) {
      hide($("linkHintCharactersContainer"));
      show($("linkHintNumbersContainer"));
      show($("waitForEnterForFilteredHintsContainer"));
    } else {
      show($("linkHintCharactersContainer"));
      hide($("linkHintNumbersContainer"));
      hide($("waitForEnterForFilteredHintsContainer"));
    }
  },

  onDownloadBackupClicked: () => {
    let backup = OptionsPage.getSettingsFromForm();
    backup = Settings2.pruneOutDefaultValues(backup);
    // TODO(philc):
    // backup.settingsVersion = settings["settingsVersion"];
    const settingsBlob = new Blob([JSON.stringify(backup, null, 2) + "\n"]);
    $("downloadBackup").href = URL.createObjectURL(settingsBlob);
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

        await Settings2.setSettings(backup);
        OptionsPage.setFormFromSettings(await Settings2.getSettings());
        $("saveOptions").disabled = true;
        $("saveOptions").textContent = "Saved";
        alert("Settings have been restored from the backup.");
      };
    }
  },
};

const initPopupPage = function () {
  chrome.tabs.query({ active: true, currentWindow: true }, function (...args) {
    const [tab] = Array.from(args[0]);
    let exclusions = null;
    const optionsUrl = chrome.runtime.getURL("pages/options.html");
    document.getElementById("optionsLink").setAttribute("href", optionsUrl);

    const tabPorts = chrome.extension.getBackgroundPage().portsForTab[tab.id];
    if (!tabPorts || !(Object.keys(tabPorts).length > 0)) {
      // The browser has disabled Vimium on this page. Place a message explaining this into the
      // popup.
      document.body.innerHTML = `\
<div style="width: 400px; margin: 5px;">
  <p style="margin-bottom: 5px;">
    Vimium is not running on this page.
  </p>
  <p style="margin-bottom: 5px;">
    Your browser does not run web extensions like Vimium on certain pages,
    usually for security reasons.
  </p>
  <p>
    Unless your browser's developers change their policy, then unfortunately it is not possible to
    make Vimium (or any other web extension, for that matter) work on this page.
  </p>
</div>\
`;
      return;
    }

    // As the active URL, we choose the most recently registered URL from a frame in the tab, or the
    // tab's own URL.
    const url = chrome.extension.getBackgroundPage().urlForTab[tab.id] || tab.url;

    const updateState = function () {
      // TODO(philc): manifest v3
      // const rule = bgExclusions.getRule(url, exclusions.readValueFromElement());
      // $("state").innerHTML = "Vimium will " +
      //   (rule && rule.passKeys
      //     ? `exclude <span class='code'>${rule.passKeys}</span>`
      //     : (rule ? "be disabled" : "be enabled"));
    };

    const onUpdated = function () {
      $("helpText").innerHTML = "Type <strong>Ctrl-Enter</strong> to save and close.";
      $("saveOptions").removeAttribute("disabled");
      $("saveOptions").textContent = "Save Changes";
      if (exclusions) {
        return updateState();
      }
    };

    const saveOptions = function () {
      Option.saveOptions();
      $("saveOptions").textContent = "Saved";
      $("saveOptions").disabled = true;
    };

    $("saveOptions").addEventListener("click", saveOptions);

    document.addEventListener("keyup", function (event) {
      if (event.ctrlKey && (event.keyCode === 13)) {
        saveOptions();
        window.close();
      }
    });

    // Populate options. Just one, here.
    exclusions = new ExclusionRulesOnPopupOption(url, "exclusionRules", onUpdated);
    exclusions.fetch();

    updateState();
    document.addEventListener("keyup", updateState);
  });

  // Install version number.
  const manifest = chrome.runtime.getManifest();
  $("versionNumber").textContent = manifest.version;
};

//
// Initialization.
document.addEventListener("DOMContentLoaded", async () => {
  DomUtils.injectUserCss(); // Manually inject custom user styles.
  const url = chrome.runtime.getURL("pages/exclusions.html");
  const response = await fetch(url);
  if (!response.ok) {
    console.error("Couldn't fetch %s", url);
    return;
  }

  const div = document.createElement("div");
  div.innerHTML = await response.text();
  $("exclusionScrollBox").appendChild(div);
  switch (location.pathname) {
    case "/pages/options.html":
      await OptionsPage.init();
      break;
    case "/pages/popup.html":
      initPopupPage();
      break;
  }
});

// Exported for use by our tests.
window.isVimiumOptionsPage = true;

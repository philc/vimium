// TODO(philc): Import JS modules here.

const ActionPage = {
  async init() {
    // Is it possible for the current tab's URL to change while this action popup is open?
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    const activeTab = tabs[0];
    this.tabUrl = activeTab.url;

    if (!await this.isVimiumInstalledInTab(activeTab.id)) {
      for (const el of Array.from(document.querySelectorAll("body > *"))) {
        el.style.display = "none";
      }
      document.querySelector("#vimiumNotEnabledMessage").style.display = "block";
      return;
    }

    document.querySelector("#optionsLink").href = chrome.runtime.getURL("pages/options.html");

    const saveOptionsEl = document.querySelector("#saveOptions");
    saveOptionsEl.addEventListener("click", (e) => this.onSave());

    document.querySelector("#cancel").addEventListener("click", () => window.close());

    const onUpdated = () => {
      saveOptionsEl.disabled = false;
      saveOptionsEl.textContent = "Save changes";
      this.syncEnabledKeysCaption();
      this.showValidationErrors();
    };

    const defaultPatternForNewRules = this.generateDefaultPattern(this.tabUrl);

    document.querySelector("#addFirstRule").addEventListener(
      "click",
      () => {
        ExclusionRulesEditor.addRow(defaultPatternForNewRules);
        this.showExclusionRulesEditor();
        onUpdated();
      },
    );

    ExclusionRulesEditor.defaultPatternForNewRules = defaultPatternForNewRules;
    ExclusionRulesEditor.init();
    ExclusionRulesEditor.addEventListener("input", onUpdated);
    const rules = Settings.get("exclusionRules").filter((r) =>
      this.tabUrl.match(this.getPatternRegExp(r.pattern))
    );
    ExclusionRulesEditor.setForm(rules);
    this.syncEnabledKeysCaption();

    if (rules.length > 0) this.showExclusionRulesEditor();
  },

  async isVimiumInstalledInTab(tabId) {
    try {
      // There is no handler in our content script for this message, but that's OK. We just want to
      // see if sending any message triggers an error.
      await chrome.tabs.sendMessage(tabId, { handler: "isVimiumInstalledInTab" });
      return true;
    } catch {
      // If there's no content script running in the activeTab, we'll get a connection error.
      return false;
    }
  },

  showValidationErrors() {
    const rows = document.querySelectorAll(".rule");
    for (const row of rows) {
      const pattern = row.querySelector("input[name=pattern]").value;
      const regExp = this.getPatternRegExp(pattern);
      const validationEl = row.querySelector(".validationMessage");
      const patternMatchesUrl = this.tabUrl.match(regExp);
      if (patternMatchesUrl) {
        row.classList.remove("validationError");
        validationEl.innerText = "";
      } else {
        row.classList.add("validationError");
        validationEl.innerText = "Pattern does not match the current URL";
      }
    }
  },

  showExclusionRulesEditor() {
    document.querySelector("#exclusionsContainer").style.display = "block";
    document.querySelector("#addFirstRuleContainer").style.display = "none";
  },

  syncEnabledKeysCaption() {
    let caption = "All";
    const rules = ExclusionRulesEditor.getRules();
    if (rules.length > 0) {
      const hasBlankPassKeysRule = rules.find((r) => r.passKeys.length == 0);
      caption = hasBlankPassKeysRule ? "No" : "Some";
    }
    document.querySelector("#howManyEnabled").innerText = caption;
  },

  async onSave() {
    let rules = await Settings.get("exclusionRules");
    // Remove any rules which match the current URL, and replace them with the contents of this dialog.
    rules = rules.filter((r) => !this.tabUrl.match(this.getPatternRegExp(r.pattern)));
    rules = rules.concat(ExclusionRulesEditor.getRules());
    Settings.set("exclusionRules", rules);
    const el = document.querySelector("#saveOptions");
    el.disabled = true;
    el.textContent = "Saved";
  },

  getPatternRegExp(patternStr) {
    return new RegExp("^" + patternStr.replace(/\*/g, ".*") + "$");
  },

  // Returns an exclusion pattern which matches the domain of the given URL.
  // This is used as the default starter pattern when the "Add rule" button is clicked.
  generateDefaultPattern(url) {
    if (/^https?:\/\/./.test(url)) {
      // The common use case is to disable Vimium at the domain level.
      // Generate "https?://www.example.com/*" from "http://www.example.com/path/to/page.html".
      // Note: IPV6 host addresses will contain "[" and "]" (which must be escaped).
      const hostname = url.split("/", 3).slice(1).join("/").replace("[", "\\[").replace(
        "]",
        "\\]",
      );
      return "https?:/" + hostname + "/*";
    } else if (/^[a-z]{3,}:\/\/./.test(url)) {
      // Anything else which seems to be a URL.
      return url.split("/", 3).join("/") + "/*";
    } else {
      return url + "*";
    }
  },
};

document.addEventListener("DOMContentLoaded", async () => {
  await Settings.onLoaded();
  ActionPage.init();
});

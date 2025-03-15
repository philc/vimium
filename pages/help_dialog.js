// The ordering we show key bindings is alphanumerical, except that special keys sort to the end.
function compareKeys(a, b) {
  a = a.replace("<", "~");
  b = b.replace("<", "~");
  if (a < b) {
    return -1;
  } else if (b < a) {
    return 1;
  } else {
    return 0;
  }
};

// This overrides the HelpDialog implementation in vimium_frontend.js. We provide aliases for the
// two HelpDialog methods required by normalMode (isShowing() and toggle()).
const HelpDialog = {
  dialogElement: null,
  isShowing() {
    return true;
  },

  // This setting is pulled out of local storage. It's false by default.
  getShowAdvancedCommands() {
    return Settings.get("helpDialog_showAdvancedCommands");
  },

  init() {
    if (this.dialogElement != null) {
      return;
    }
    this.dialogElement = document.querySelector("#vimiumHelpDialog");

    const closeButton = this.dialogElement.querySelector(".closeButton");
    closeButton.addEventListener("click", (event) => {
      event.preventDefault();
      this.hide();
    }, false);

    // "auxclick" handles a click with the middle mouse button.
    const optionsLink = document.querySelector("#helpDialogOptionsPage");
    for (const eventName of ["click", "auxclick"]) {
      optionsLink.addEventListener(eventName, (event) => {
        event.preventDefault();
        chrome.runtime.sendMessage({ handler: "openOptionsPageInNewTab" });
      }, false);
    }

    document.querySelector("#toggleAdvancedCommands").addEventListener(
      "click",
      HelpDialog.toggleAdvancedCommands.bind(HelpDialog),
      false,
    );

    document.documentElement.addEventListener("click", (event) => {
      if (!this.dialogElement.contains(event.target)) {
        this.hide();
      }
    }, false);
  },

  async show({ showAllCommandDetails }) {
    const title = showAllCommandDetails ? "Command Listing" : "Help";
    document.getElementById("help-dialog-title").textContent = title;
    document.getElementById("help-dialog-version").textContent = Utils.getCurrentVersion();

    const entryTemplate = document.querySelector("#helpDialogEntry").content;
    const entryBindingsTemplate = document.querySelector("#helpDialogEntryBindingsOnly").content;
    const keysTemplate = document.querySelector("#keysTemplate").content;
    const commandNameTemplate = document.querySelector("#commandNameTemplate").content;

    const { helpPageData } = await chrome.storage.session.get("helpPageData");
    for (const group of Object.keys(helpPageData)) {
      const commands = helpPageData[group];
      const container = this.dialogElement.querySelector(`#help-dialog-${group}`);
      container.innerHTML = "";

      for (const command of commands) {
        const unbound = command.keys.length == 0;
        if (unbound && !showAllCommandDetails) continue;

        let keysEl = null;
        let descEl = null;

        // TODO(philc): This layout logic for displaying long commands seems unnecessarily
        // complicated.
        const useTwoRows = command.keys.join(", ").length >= 12;
        if (!useTwoRows) {
          const node = entryTemplate.cloneNode(true);
          container.appendChild(node);
          const el = container.lastElementChild;
          if (command.advanced) {
            el.classList.add("advanced");
          }
          keysEl = descEl = el;
        } else {
          let node = entryBindingsTemplate.cloneNode(true);
          container.appendChild(node);
          let el = container.lastElementChild;
          if (command.advanced) {
            el.classList.add("advanced");
          }
          keysEl = el;

          node = entryTemplate.cloneNode(true);
          container.appendChild(node);
          el = container.lastElementChild;
          if (command.advanced) {
            el.classList.add("advanced");
          }
          descEl = el;
        }

        const MAX_LENGTH = 50;
        // - 3 because 3 is the length of the ellipsis string, "..."
        const desiredOptionsLength = Math.max(0, MAX_LENGTH - command.description.length - 3);
        // If command + options is too long: truncate, add ellipsis, and set hover.
        let optionsTruncated = command.options.substring(0, desiredOptionsLength);
        if ((command.description.length + command.options.length) > MAX_LENGTH) {
          optionsTruncated += "...";
          // Full option list (non-ellipsized) will be visible on hover.
          descEl.querySelector(".vimiumHelpDescription").title = command.options;
        }
        const optionsString = command.options ? ` (${optionsTruncated})` : "";
        const fullDescription = `${command.description}${optionsString}`;
        descEl.querySelector(".vimiumHelpDescription").textContent = fullDescription;

        keysEl = keysEl.querySelector(".vimiumKeyBindings");
        const keysTemplate = document.querySelector("#keysTemplate").content;
        for (var key of command.keys.sort(compareKeys)) {
          const node = keysTemplate.cloneNode(true);
          keysEl.appendChild(node);
          const el = keysEl.lastElementChild;
          el.querySelector(".vimiumHelpDialogKey").textContent = key;
        }

        // Strip off the trailing ", " if necessary.
        const lastEl = keysEl.lastElementChild;
        if (lastEl) {
          lastEl.removeChild(lastEl.querySelector(".commaSeparator"));
        }

        if (showAllCommandDetails) {
          const descEl2 = descEl.querySelector(".vimiumHelpDescription");
          const node = commandNameTemplate.cloneNode(true);
          descEl2.appendChild(node);
          const el = descEl2.lastElementChild;
          const commandNameEl = el.querySelector(".vimiumCopyCommandNameName");
          commandNameEl.textContent = command.command;
          commandNameEl.title = `Click to copy \"${command.command}\" to clipboard.`;
          commandNameEl.addEventListener("click", function () {
            HUD.copyToClipboard(commandNameEl.textContent);
            HUD.show(`Yanked ${commandNameElement.textContent}.`, 2000);
          });
        }
      }
    }

    this.showAdvancedCommands(this.getShowAdvancedCommands());

    // "Click" the dialog element (so that it becomes scrollable).
    DomUtils.simulateClick(this.dialogElement);
  },

  hide() {
    UIComponentServer.hide();
  },

  toggle() {
    this.hide();
  },

  //
  // Advanced commands are hidden by default so they don't overwhelm new and casual users.
  //
  toggleAdvancedCommands(event) {
    const container = document.getElementById("vimiumHelpDialogContainer");
    const scrollHeightBefore = container.scrollHeight;
    event.preventDefault();
    const showAdvanced = HelpDialog.getShowAdvancedCommands();
    HelpDialog.showAdvancedCommands(!showAdvanced);
    Settings.set("helpDialog_showAdvancedCommands", !showAdvanced);
    // Try to keep the "show advanced commands" button in the same scroll position.
    const scrollHeightDelta = container.scrollHeight - scrollHeightBefore;
    if (scrollHeightDelta > 0) {
      container.scrollTop += scrollHeightDelta;
    }
  },

  showAdvancedCommands(visible) {
    const caption = visible ? "Hide advanced commands" : "Show advanced commands";
    document.getElementById("toggleAdvancedCommands").textContent = caption;
    if (visible) {
      HelpDialog.dialogElement.classList.add("showAdvanced");
    } else {
      HelpDialog.dialogElement.classList.remove("showAdvanced");
    }
  },
};

UIComponentServer.registerHandler(async function (event) {
  await Settings.onLoaded();
  await Utils.populateBrowserInfo();
  switch (event.data.name != null ? event.data.name : event.data) {
    case "hide":
      HelpDialog.hide();
      break;
    case "activate":
      HelpDialog.init();
      await HelpDialog.show(event.data);
      // If we abandoned (see below) in a mode with a HUD indicator, then we have to reinstate it.
      Mode.setIndicator();
      break;
    case "hidden":
      // Abandon any HUD which might be showing within the help dialog.
      HUD.abandon();
      break;
  }
});

document.addEventListener("DOMContentLoaded", async () => {
  await Settings.onLoaded();
  DomUtils.injectUserCss(); // Manually inject custom user styles.
});

globalThis.HelpDialog = HelpDialog;
globalThis.isVimiumHelpDialog = true;

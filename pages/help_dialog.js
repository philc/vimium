/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS203: Remove `|| {}` from converted for-own loops
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const $ = (id) => document.getElementById(id);
const $$ = (element, selector) => element.querySelector(selector);

// The ordering we show key bindings is alphanumerical, except that special keys sort to the end.
const compareKeys = function (a, b) {
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
    this.dialogElement = document.getElementById("vimiumHelpDialog");

    this.dialogElement.getElementsByClassName("closeButton")[0].addEventListener(
      "click",
      (clickEvent) => {
        clickEvent.preventDefault();
        this.hide();
      },
      false,
    );

    // "auxclick" handles a click with the middle mouse button.
    for (let eventName of ["click", "auxclick"]) {
      document.getElementById("helpDialogOptionsPage").addEventListener(
        eventName,
        (event) => {
          event.preventDefault();
          chrome.runtime.sendMessage({ handler: "openOptionsPageInNewTab" });
        },
        false,
      );
    }

    document.getElementById("toggleAdvancedCommands")
      .addEventListener("click", HelpDialog.toggleAdvancedCommands.bind(HelpDialog), false);

    document.documentElement.addEventListener("click", (event) => {
      if (!this.dialogElement.contains(event.target)) {
        this.hide();
      }
    }, false);
  },

  instantiateHtmlTemplate(parentNode, templateId, callback) {
    const templateContent = document.querySelector(templateId).content;
    const node = document.importNode(templateContent, true);
    parentNode.appendChild(node);
    callback(parentNode.lastElementChild);
  },

  show({ showAllCommandDetails }) {
    $("help-dialog-title").textContent = showAllCommandDetails ? "Command Listing" : "Help";
    $("help-dialog-version").textContent = Utils.getCurrentVersion();

    chrome.storage.session.get("helpPageData", ({ helpPageData }) => {
      for (let group of Object.keys(helpPageData)) {
        const commands = helpPageData[group];
        const container = this.dialogElement.querySelector(`#help-dialog-${group}`);
        container.innerHTML = "";

        for (var command of Array.from(commands)) {
          if (!showAllCommandDetails && command.keys.length == 0) {
            continue;
          }

          let keysElement = null;
          let descriptionElement = null;

          const useTwoRows = command.keys.join(", ").length >= 12;
          if (!useTwoRows) {
            this.instantiateHtmlTemplate(container, "#helpDialogEntry", function (element) {
              if (command.advanced) {
                element.classList.add("advanced");
              }
              keysElement = descriptionElement = element;
            });
          } else {
            this.instantiateHtmlTemplate(
              container,
              "#helpDialogEntryBindingsOnly",
              function (element) {
                if (command.advanced) {
                  element.classList.add("advanced");
                }
                keysElement = element;
              },
            );
            this.instantiateHtmlTemplate(container, "#helpDialogEntry", function (element) {
              if (command.advanced) {
                element.classList.add("advanced");
              }
              descriptionElement = element;
            });
          }

          $$(descriptionElement, ".vimiumHelpDescription").textContent = command.description;

          keysElement = $$(keysElement, ".vimiumKeyBindings");
          let lastElement = null;
          for (var key of command.keys.sort(compareKeys)) {
            this.instantiateHtmlTemplate(keysElement, "#keysTemplate", function (element) {
              lastElement = element;
              $$(element, ".vimiumHelpDialogKey").textContent = key;
            });
          }

          // And strip off the trailing ", ", if necessary.
          if (lastElement) {
            lastElement.removeChild($$(lastElement, ".commaSeparator"));
          }

          if (showAllCommandDetails) {
            this.instantiateHtmlTemplate(
              $$(descriptionElement, ".vimiumHelpDescription"),
              "#commandNameTemplate",
              function (element) {
                const commandNameElement = $$(element, ".vimiumCopyCommandNameName");
                commandNameElement.textContent = command.command;
                commandNameElement.title = `Click to copy \"${command.command}\" to clipboard.`;
                commandNameElement.addEventListener("click", function () {
                  HUD.copyToClipboard(commandNameElement.textContent);
                  HUD.show(`Yanked ${commandNameElement.textContent}.`, 2000);
                });
              },
            );
          }
          // }
        }
      }

      this.showAdvancedCommands(this.getShowAdvancedCommands());

      // "Click" the dialog element (so that it becomes scrollable).
      DomUtils.simulateClick(this.dialogElement);
    });
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
    const vimiumHelpDialogContainer = $("vimiumHelpDialogContainer");
    const scrollHeightBefore = vimiumHelpDialogContainer.scrollHeight;
    event.preventDefault();
    const showAdvanced = HelpDialog.getShowAdvancedCommands();
    HelpDialog.showAdvancedCommands(!showAdvanced);
    Settings.set("helpDialog_showAdvancedCommands", !showAdvanced);
    // Try to keep the "show advanced commands" button in the same scroll position.
    const scrollHeightDelta = vimiumHelpDialogContainer.scrollHeight - scrollHeightBefore;
    if (scrollHeightDelta > 0) {
      vimiumHelpDialogContainer.scrollTop += scrollHeightDelta;
    }
  },

  showAdvancedCommands(visible) {
    document.getElementById("toggleAdvancedCommands").textContent = visible
      ? "Hide advanced commands"
      : "Show advanced commands";

    // Add/remove the showAdvanced class to show/hide advanced commands.
    const addOrRemove = visible ? "add" : "remove";
    HelpDialog.dialogElement.classList[addOrRemove]("showAdvanced");
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
      HelpDialog.show(event.data);
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

window.HelpDialog = HelpDialog;
window.isVimiumHelpDialog = true;

// This is the order they will be shown in the help dialog.
//
// Properties:
// - advanced: advanced commands are not shown in the help dialog by default.
// - background: whether this command has to be run by the background page.
// - desc: shown in the help dialog and command listing page.
// - group: commands are displayed in groups in the help dialog and command listing.
// - noRepeat: whether this command can be used with a count key prefix.
// - repeatLimit: the number of allowed repetitions of this command before the user is prompted for
//   confirmation.
// - topFrame: whether this command must be run only in the top frame of a page.
//
const allCommands = [
  //
  // Navigation
  //

  {
    name: "scrollDown",
    desc: "Scroll down",
    group: "navigation",
  },

  {
    name: "scrollUp",
    desc: "Scroll up",
    group: "navigation",
  },

  {
    name: "scrollToTop",
    desc: "Scroll to the top of the page",
    group: "navigation",
  },

  {
    name: "scrollToBottom",
    desc: "Scroll to the bottom of the page",
    group: "navigation",
  },

  {
    name: "scrollPageDown",
    desc: "Scroll a half page down",
    group: "navigation",
  },

  {
    name: "scrollPageUp",
    desc: "Scroll a half page up",
    group: "navigation",
  },

  {
    name: "scrollFullPageDown",
    desc: "Scroll a full page down",
    group: "navigation",
  },

  {
    name: "scrollFullPageUp",
    desc: "Scroll a full page up",
    group: "navigation",
  },

  {
    name: "scrollLeft",
    desc: "Scroll left",
    group: "navigation",
  },

  {
    name: "scrollRight",
    desc: "Scroll right",
    group: "navigation",
    advanced: true,
  },

  {
    name: "scrollToLeft",
    desc: "Scroll all the way to the left",
    group: "navigation",
    advanced: true,
  },

  {
    name: "scrollToRight",
    desc: "Scroll all the way to the right",
    group: "navigation",
  },

  {
    name: "reload",
    desc: "Reload the page",
    group: "navigation",
    background: true,
    options: {
      hard: "Perform a hard reload, forcing the browser to bypass its cache.",
    },
  },

  {
    name: "copyCurrentUrl",
    desc: "Copy the current URL to the clipboard",
    group: "navigation",
    noRepeat: true,
  },

  {
    name: "openCopiedUrlInCurrentTab",
    desc: "Open the clipboard's URL in the current tab",
    group: "navigation",
    noRepeat: true,
  },

  {
    name: "openCopiedUrlInNewTab",
    desc: "Open the clipboard's URL in a new tab",
    group: "navigation",
    noRepeat: true,
  },

  {
    name: "goUp",
    desc: "Go up the URL hierarchy",
    group: "navigation",
    advanced: true,
  },

  {
    name: "goToRoot",
    desc: "Go to the root of current URL hierarchy",
    group: "navigation",
    advanced: true,
  },

  {
    name: "enterInsertMode",
    desc: "Enter insert mode",
    group: "navigation",
    noRepeat: true,
  },

  {
    name: "enterVisualMode",
    desc: "Enter visual mode",
    group: "navigation",
    noRepeat: true,
  },

  {
    name: "enterVisualLineMode",
    desc: "Enter visual line mode",
    group: "navigation",
    advanced: true,
    noRepeat: true,
  },

  {
    name: "passNextKey",
    desc: "Pass the next key to the page",
    group: "navigation",
    advanced: true,
  },

  {
    name: "focusInput",
    desc: "Focus the first text input on the page",
    group: "navigation",
  },

  {
    name: "LinkHints.activateMode",
    desc: "Open a link in the current tab",
    options: {
      action: "<code>action</code>: one of <code>hover</code>, <code>focus</code>, " +
        "<code>copy-text</code>. When a link is selected, instead of clicking on the link, " +
        "perform the specified action.",
    },
    group: "navigation",
    advanced: true,
  },

  {
    name: "LinkHints.activateModeToOpenInNewTab",
    desc: "Open a link in a new tab",
    group: "navigation",
  },

  {
    name: "LinkHints.activateModeToOpenInNewForegroundTab",
    desc: "Open a link in a new tab & switch to it",
    group: "navigation",
  },

  {
    name: "LinkHints.activateModeWithQueue",
    desc: "Open multiple links in a new tab",
    group: "navigation",
    advanced: true,
    noRepeat: true,
  },

  {
    name: "LinkHints.activateModeToDownloadLink",
    desc: "Download link url",
    group: "navigation",
    advanced: true,
  },

  {
    name: "LinkHints.activateModeToOpenIncognito",
    desc: "Open a link in incognito window",
    group: "navigation",
    advanced: true,
  },

  {
    name: "LinkHints.activateModeToCopyLinkUrl",
    desc: "Copy a link URL to the clipboard",
    group: "navigation",
    advanced: true,
  },

  {
    name: "goPrevious",
    desc: "Follow the link labeled previous or <",
    group: "navigation",
    advanced: true,
    noRepeat: true,
  },

  {
    name: "goNext",
    desc: "Follow the link labeled next or >",
    group: "navigation",
    advanced: true,
    noRepeat: true,
  },

  {
    name: "nextFrame",
    desc: "Select the next frame on the page",
    group: "navigation",
    background: true,
  },

  {
    name: "mainFrame",
    desc: "Select the page's main/top frame",
    group: "navigation",
    topFrame: true,
    noRepeat: true,
  },

  {
    name: "Marks.activateCreateMode",
    desc: "Create a new mark",
    group: "navigation",
    advanced: true,
    noRepeat: true,
  },

  {
    name: "Marks.activateGotoMode",
    desc: "go to a mark",
    group: "navigation",
    advanced: true,
    noRepeat: true,
  },

  //
  // Vomnibar
  //

  {
    name: "Vomnibar.activate",
    desc: "Open URL, bookmark or history entry",
    group: "vomnibar",
    topFrame: true,
  },

  {
    name: "Vomnibar.activateInNewTab",
    desc: "Open URL, bookmark or history entry in a new tab",
    group: "vomnibar",
    topFrame: true,
  },

  {
    name: "Vomnibar.activateBookmarks",
    desc: "Open a bookmark",
    group: "vomnibar",
    topFrame: true,
  },

  {
    name: "Vomnibar.activateBookmarksInNewTab",
    desc: "Open a bookmark in a new tab",
    group: "vomnibar",
    topFrame: true,
  },

  {
    name: "Vomnibar.activateTabSelection",
    desc: "Search through your open tabs",
    group: "vomnibar",
    topFrame: true,
  },

  {
    name: "Vomnibar.activateEditUrl",
    desc: "Edit the current URL",
    group: "vomnibar",
    topFrame: true,
  },

  {
    name: "Vomnibar.activateEditUrlInNewTab",
    desc: "Edit the current URL and open in a new tab",
    group: "vomnibar",
    topFrame: true,
  },

  //
  // Find
  //

  {
    name: "enterFindMode",
    desc: "Enter find mode.",
    group: "find",
    noRepeat: true,
  },

  {
    name: "performFind",
    desc: "Cycle forward to the next find match",
    group: "find",
  },

  {
    name: "performBackwardsFind",
    desc: "Cycle backward to the previous find match",
    group: "find",
  },

  {
    name: "findSelected",
    desc: "Find the selected text",
    group: "find",
    advanced: true,
  },

  {
    name: "findSelectedBackwards",
    desc: "Find the selected text, searching backwards",
    group: "find",
    advanced: true,
  },

  //
  // History
  //

  {
    name: "goBack",
    desc: "Go back in history",
    group: "history",
  },

  {
    name: "goForward",
    desc: "Go forward in history",
    group: "history",
  },

  //
  // Tabs
  //

  {
    name: "createTab",
    desc: "Create new tab",
    group: "tabs",
    background: true,
    repeatLimit: 20,
  },

  {
    name: "previousTab",
    desc: "Go one tab left",
    group: "tabs",
    background: true,
  },

  {
    name: "nextTab",
    desc: "Go one tab right",
    group: "tabs",
    background: true,
  },

  {
    name: "visitPreviousTab",
    desc: "Go to previously-visited tab",
    group: "tabs",
    background: true,
  },

  {
    name: "firstTab",
    desc: "Go to the first tab",
    group: "tabs",
    background: true,
  },

  {
    name: "lastTab",
    desc: "Go to the last tab",
    group: "tabs",
    background: true,
  },

  {
    name: "duplicateTab",
    desc: "Duplicate current tab",
    group: "tabs",
    background: true,
    repeatLimit: 20,
  },

  {
    name: "togglePinTab",
    desc: "Pin or unpin current tab",
    group: "tabs",
    background: true,
  },

  {
    name: "toggleMuteTab",
    desc: "Mute or unmute current tab",
    group: "tabs",
    background: true,
    noRepeat: true,
  },

  {
    name: "removeTab",
    desc: "Close current tab",
    group: "tabs",
    background: true,
    // Don't close (in one command invocation) more than the number of tabs that can be re-opened by
    // the browser.
    repeatLimit: chrome.sessions?.MAX_SESSION_RESULTS || 25,
  },

  {
    name: "restoreTab",
    desc: "Restore closed tab",
    group: "tabs",
    background: true,
    repeatLimit: 20,
  },

  {
    name: "moveTabToNewWindow",
    desc: "Move tab to new window",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "closeTabsOnLeft",
    desc: "Close tabs on the left",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "closeTabsOnRight",
    desc: "Close tabs on the right",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "closeOtherTabs",
    desc: "Close all other tabs",
    group: "tabs",
    advanced: true,
    background: true,
    noRepat: true,
  },

  {
    name: "moveTabLeft",
    desc: "Move tab to the left",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "moveTabRight",
    desc: "Move tab to the right",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "setZoom",
    desc: "Set zoom",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "zoomIn",
    desc: "Zoom in",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "zoomOut",
    desc: "Zoom out",
    group: "tabs",
    advanced: true,
    background: true,
  },

  {
    name: "zoomReset",
    desc: "Reset zoom",
    group: "tabs",
    advanced: true,
    background: true,
  },

  //
  // Misc
  //

  {
    name: "toggleViewSource",
    desc: "View page source",
    group: "misc",
    advanced: true,
    noRepeat: true,
  },

  {
    name: "showHelp",
    desc: "Show help",
    group: "misc",
    noRepeat: true,
    topFrame: true,
  },
];

globalThis.allCommands = allCommands;

const allCommands = [
  {
    name: "showHelp",
    desc: "Show help",
    noRepeat: true,
    topFrame: true,
    group: "misc",
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
    name: "scrollDown",
    desc: "Scroll down",
    group: "navigation",
  },

  {
    name: "copyCurrentUrl",
    desc: "Copy the current URL to the clipboard",
    group: "navigation",
    noRepeat: true,
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
    name: "createTab",
    desc: "Create new tab",
    group: "tabs",
    background: true,
    repeatLimit: 20,
  },

  {
    name: "Vomnibar.activate",
    desc: "Open URL, bookmark or history entry",
    group: "vomnibar",
    topFrame: true,
  },


  {
    name: "goBack",
    desc: "Go back in history",
    group: "history",
  },

  {
    name: "goGorward",
    desc: "Go forward in history",
    group: "history",
  },

];

globalThis.allCommands = allCommands;

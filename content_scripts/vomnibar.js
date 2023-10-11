//
// This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
//
const Vomnibar = {
  vomnibarUI: null,

  // sourceFrameId here (and below) is the ID of the frame from which this request originates, which
  // may be different from the current frame.

  activate(sourceFrameId, registryEntry) {
    const options = Object.assign({}, registryEntry.options, { completer: "omni" });
    this.open(sourceFrameId, options);
  },

  activateInNewTab(sourceFrameId, registryEntry) {
    const options = Object.assign({}, registryEntry.options, { completer: "omni", newTab: true });
    this.open(sourceFrameId, options);
  },

  activateTabSelection(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "tabs",
      selectFirst: true,
    });
  },

  activateBookmarks(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "bookmarks",
      selectFirst: true,
    });
  },

  activateBookmarksInNewTab(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "bookmarks",
      selectFirst: true,
      newTab: true,
    });
  },

  activateEditUrl(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "omni",
      selectFirst: false,
      query: window.location.href,
    });
  },

  activateEditUrlInNewTab(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "omni",
      selectFirst: false,
      query: window.location.href,
      newTab: true,
    });
  },

  init() {
    if (!this.vomnibarUI) {
      this.vomnibarUI = new UIComponent("pages/vomnibar.html", "vomnibarFrame", function () {});
    }
  },

  // Opens the vomnibar.
  // - options: a map with values
  //     completer   - The name of the completer to fetch results from.
  //     query       - Optional. Text to prefill the Vomnibar with.
  //     selectFirst - Optional, boolean. Whether to select the first entry.
  //     newTab      - Optional, boolean. Whether to open the result in a new tab.
  open(sourceFrameId, options) {
    this.init();
    // The Vomnibar cannot coexist with the help dialog (it causes focus issues).
    HelpDialog.abort();
    this.vomnibarUI.activate(
      Object.assign(options, { name: "activate", sourceFrameId, focus: true }),
    );
  },
};

window.Vomnibar = Vomnibar;

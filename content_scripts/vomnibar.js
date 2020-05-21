//
// This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
//
const Vomnibar = {
  vomnibarUI: null,

  // Extract any additional options from the command's registry entry.
  extractOptionsFromRegistryEntry(registryEntry, callback) {
    return callback ? callback(Object.assign({}, registryEntry.options)) : null;
  },

  // sourceFrameId here (and below) is the ID of the frame from which this request originates, which may be
  // different from the current frame.

  activate(sourceFrameId, registryEntry) {
    return this.extractOptionsFromRegistryEntry(registryEntry, options => {
      return this.open(sourceFrameId, Object.assign(options, {completer:"omni"}));
    });
  },

  activateInNewTab(sourceFrameId, registryEntry) {
    return this.extractOptionsFromRegistryEntry(registryEntry, options => {
      return this.open(sourceFrameId, Object.assign(options, {completer:"omni", newTab: true}));
    });
  },

  activateTabSelection(sourceFrameId) {
    return this.open(sourceFrameId, {
      completer: "tabs",
      selectFirst: true
    });
  },

  activateBookmarks(sourceFrameId) {
    return this.open(sourceFrameId, {
      completer: "bookmarks",
      selectFirst: true
    });
  },

  activateBookmarksInNewTab(sourceFrameId) {
    return this.open(sourceFrameId, {
      completer: "bookmarks",
      selectFirst: true,
      newTab: true
    });
  },

  activateEditUrl(sourceFrameId) {
    return this.open(sourceFrameId, {
      completer: "omni",
      selectFirst: false,
      query: window.location.href
    });
  },

  activateEditUrlInNewTab(sourceFrameId) {
    return this.open(sourceFrameId, {
      completer: "omni",
      selectFirst: false,
      query: window.location.href,
      newTab: true
    });
  },

  init() {
    if (!this.vomnibarUI)
      this.vomnibarUI = new UIComponent("pages/vomnibar.html", "vomnibarFrame", function() {})
  },

  // This function opens the vomnibar. It accepts options, a map with the values:
  //   completer   - The completer to fetch results from.
  //   query       - Optional. Text to prefill the Vomnibar with.
  //   selectFirst - Optional, boolean. Whether to select the first entry.
  //   newTab      - Optional, boolean. Whether to open the result in a new tab.
  open(sourceFrameId, options) {
    this.init();
    // The Vomnibar cannot coexist with the help dialog (it causes focus issues).
    HelpDialog.abort();
    return this.vomnibarUI.activate(Object.assign(options, { name: "activate", sourceFrameId, focus: true }));
  }
};

global.Vomnibar = Vomnibar;

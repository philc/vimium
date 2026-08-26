// Themes are directories containing a full set of Vimium's stylesheets, located in themes/<name>.
// The currently active theme is stored in the "theme" setting.
const Themes = {
  defaultTheme: "default",

  availableThemes: [
    "default",
    "ventura",
  ],

  // Display names for the options page's theme picker, keyed by theme name.
  displayNames: {
    "default": "Default",
    "ventura": "macOS Ventura",
  },

  // The set of files which each theme directory provides. Paths are relative to the repository
  // root, and mirror the locations of the corresponding default stylesheets.
  themedFilePaths: [
    "content_scripts/vimium.css",
    "pages/action.css",
    "pages/command_listing.css",
    "pages/help_dialog_page.css",
    "pages/hud_page.css",
    "pages/key_mappings.css",
    "pages/options.css",
    "pages/vomnibar_page.css",
  ],

  // Returns the path of `filePath` (one of themedFilePaths) within the given theme.
  getThemePath(theme, filePath) {
    return `themes/${theme}/${filePath}`;
  },

  isValidTheme(theme) {
    return this.availableThemes.includes(theme);
  },
};

globalThis.Themes = Themes;

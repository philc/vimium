/*
 * Used by everyone to manipulate localStorage.
 */
var settings = {

  defaults: {
    scrollStepSize: 60,
    linkHintCharacters: "sadfjklewcmpgh",
    filterLinkHints: false,
    hideHud: false,
    userDefinedLinkHintCss:
      "div > .vimiumHintMarker {" + "\n" +
      "/* linkhint boxes */ " + "\n" +
      "background-color: yellow;" + "\n" +
      "border: 1px solid #E3BE23;" + "\n" +
      "}" + "\n\n" +
      "div > .vimiumHintMarker span {" + "\n" +
      "/* linkhint text */ " + "\n" +
      "color: black;" + "\n" +
      "font-weight: bold;" + "\n" +
      "font-size: 12px;" + "\n" +
      "}" + "\n\n" +
      "div > .vimiumHintMarker > .matchingCharacter {" + "\n" +
      "}",
    excludedUrls: "http*://mail.google.com/*\n" +
                  "http*://www.google.com/reader/*\n",

    // NOTE : If a page contains both a single angle-bracket link and a double angle-bracket link, then in
    // most cases the single bracket link will be "prev/next page" and the double bracket link will be
    // "first/last page", so we put the single bracket first in the pattern string so that it gets searched
    // for first.

    // "\bprev\b,\bprevious\b,\bback\b,<,←,«,≪,<<"
    previousPatterns: "prev,previous,back,<,\u2190,\xab,\u226a,<<",
    // "\bnext\b,\bmore\b,>,→,»,≫,>>"
    nextPatterns: "next,more,>,\u2192,\xbb,\u226b,>>",
  },

  init: function() {
    // settingsVersion was introduced in v1.31, and is used to coordinate data migration. We do not use
    // previousVersion as it is used to coordinate the display of the upgrade message, and is not updated
    // early enough when the extension loads.
    // 1.31 was also the version where we converted all localStorage values to JSON.
    if (!this.has("settingsVersion")) {
      for (var key in localStorage) {
        // filterLinkHints' checkbox state used to be stored as a string
        if (key == "filterLinkHints")
          localStorage[key] = localStorage[key] === "true" ? true : false;
        else
          localStorage[key] = JSON.stringify(localStorage[key]);
      }
      this.set("settingsVersion", utils.getCurrentVersion());
    }
  },

  get: function(key) {
    if (!(key in localStorage))
      return this.defaults[key];
    else
      return JSON.parse(localStorage[key]);
  },

  set: function(key, value) {
    // don't store the value if it is equal to the default, so we can change the defaults in the future
    if (value === this.defaults[key])
      this.clear(key);
    else
      localStorage[key] = JSON.stringify(value);
  },

  clear: function(key) {
    delete localStorage[key];
  },

  has: function(key) {
    return key in localStorage;
  },

};

settings.init();

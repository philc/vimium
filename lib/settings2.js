// WIP rewrite of settings.js
const defaultOptions = {
  scrollStepSize: 60,
  smoothScroll: true,
  keyMappings: "# Insert your preferred key mappings here.",
  linkHintCharacters: "sadfjklewcmpgh",
  linkHintNumbers: "0123456789",
  filterLinkHints: false,
  hideHud: false,
  userDefinedLinkHintCss: `\
div > .vimiumHintMarker {
/* linkhint boxes */
background: -webkit-gradient(linear, left top, left bottom, color-stop(0%,#FFF785),
  color-stop(100%,#FFC542));
border: 1px solid #E3BE23;
}

div > .vimiumHintMarker span {
/* linkhint text */
color: black;
font-weight: bold;
font-size: 12px;
}

div > .vimiumHintMarker > .matchingCharacter {
}\
`,
  // Default exclusion rules.
  exclusionRules: [
    // Disable Vimium on Gmail.
    {
      passKeys: "",
      pattern: "https?://mail.google.com/*",
    },
  ],

  // NOTE: If a page contains both a single angle-bracket link and a double angle-bracket link,
  // then in most cases the single bracket link will be "prev/next page" and the double bracket
  // link will be "first/last page", so we put the single bracket first in the pattern string so
  // that it gets searched for first.

  // "\bprev\b,\bprevious\b,\bback\b,<,‹,←,«,≪,<<"
  previousPatterns: "prev,previous,back,older,<,\u2039,\u2190,\xab,\u226a,<<",
  // "\bnext\b,\bmore\b,>,›,→,»,≫,>>"
  nextPatterns: "next,more,newer,>,\u203a,\u2192,\xbb,\u226b,>>",
  // default/fall back search engine
  searchUrl: "https://www.google.com/search?q=",
  // put in an example search engine
  searchEngines: `\
w: https://www.wikipedia.org/w/index.php?title=Special:Search&search=%s Wikipedia

# More examples.
#
# (Vimium supports search completion Wikipedia, as
# above, and for these.)
#
# g: https://www.google.com/search?q=%s Google
# l: https://www.google.com/search?q=%s&btnI I'm feeling lucky...
# y: https://www.youtube.com/results?search_query=%s Youtube
# gm: https://www.google.com/maps?q=%s Google maps
# b: https://www.bing.com/search?q=%s Bing
# d: https://duckduckgo.com/?q=%s DuckDuckGo
# az: https://www.amazon.com/s/?field-keywords=%s Amazon
# qw: https://www.qwant.com/?q=%s Qwant\
`,
  newTabUrl: "about:newtab",
  grabBackFocus: false,
  regexFindMode: false,
  waitForEnterForFilteredHints: false, // Note: this defaults to true for new users; see below.

  settingsVersion: "",
  helpDialog_showAdvancedCommands: false,
  optionsPage_showAdvancedOptions: false,
  passNextKeyKeys: [],
  ignoreKeyboardLayout: false,
};

const Settings2 = {
  settingsKey: "settings-v1",
  // TODO(philc): Listen for the onchanged event and rebuild the storage cache.
  _settings: null,

  onLoaded() {
    const p = new Promise(async (resolve, reject) => {
      if (!this.isLoaded()) {
        await this.load();
      }
      resolve();
    });
    return p;
  },

  async load() {
    // NOTE(philc): If we change the schema of the settings object in a backwards-incompatible way,
    // then we can fetch the whole storage object here and migrate any old settings the user has to
    // the new schema.
    const settings = await chrome.storage.sync.get(this.settingsKey);
    const values = settings[this.settingsKey] || {};
    this._settings = Object.assign(globalThis.structuredClone(defaultOptions), values);
  },

  isLoaded() {
    return this._settings != null;
  },

  get(key) {
    if (!this.isLoaded()) {
      throw `Getting the setting ${key} before settings have been loaded.`;
    }
    return globalThis.structuredClone(this._settings[key]);
  },

  async set(key, value) {
    if (!this.isLoaded()) {
      throw `Writing the setting ${key} before settings have been loaded.`;
    }
    this._settings[key] = value;
    await this.setSettings(this._settings);
  },

  getSettings() {
    return globalThis.structuredClone(this._settings);
  },

  async setSettings(settings) {
    const o = {};
    // TODO(philc): If settings.version is old, then migrate it before storing.
    o[this.settingsKey] = this.pruneOutDefaultValues(settings);
    await chrome.storage.sync.set(o);
    await this.load();
  },

  // Remove the keys from `settings` which are equal to the default values for those keys.
  pruneOutDefaultValues(settings) {
    const clonedSettings = globalThis.structuredClone(settings);
    for (const [k, v] of Object.entries(settings)) {
      if (JSON.stringify(v) == JSON.stringify(defaultOptions[k])) {
        delete clonedSettings[k];
      }
    }
    return clonedSettings;
  },
  // Saves the new mapping in Settings, and broadcasts a message to the SheetKeys content scripts in
  // all tabs that a key mapping has changed.
  // async changeKeyMapping(commandName, keyMapping) {
  //   if (commandName == null || keyMapping == "") {
  //     throw new Error(`Invalid command name or key mapping '${commandName}', '${keyMapping}'`);
  //   }
  //   const settings = await Settings.get();
  //   settings.keyMappings[commandName] = keyMapping;
  //   Settings.set(settings);
  //   chrome.runtime.sendMessage(null, "keyMappingChange");
  // },

  // Returns a map of { mode => { commandName => keyString } }
  // async loadUserKeyMappings() {
  //   const settings = await Settings.get();
  //   const mappings = {};
  //   // Do a deep clone of the default mappings.
  //   for (const mode of Object.keys(Commands.defaultMappings)) {
  //     mappings[mode] = Object.assign({}, Commands.defaultMappings[mode]);
  //   }
  //   // We only allow the user to bind keys in normal mode, for conceptual and UI simplicity.
  //   mappings.normal = Object.assign(mappings.normal, settings.keyMappings);
  //   return mappings;
  // },
};

globalThis.Settings2 = Settings2;

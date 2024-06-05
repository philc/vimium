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
# az: https://www.amazon.com/s/?field-keywords=%s
# qw: https://www.qwant.com/?q=%s Qwant\
`,
  newTabUrl: "about:newtab", // Equal to the value of chromeNewTabUrl in tab_operations.js.
  grabBackFocus: false,
  regexFindMode: false,
  waitForEnterForFilteredHints: true,
  helpDialog_showAdvancedCommands: false,
  ignoreKeyboardLayout: false,
};

/*
 * This class fetches and exposes the view over Vimium's settings data, which is stored in
 * chrome.storage. It merges the user's customizations into the default setting values.
 * It dispatches the "change" event when the settings have been changed.
 */
const Settings = {
  _settings: null,
  _chromeStorageListenerInstalled: false,

  defaultOptions: defaultOptions,

  async onLoaded() {
    if (!this.isLoaded()) {
      await this.load();
    }
  },

  async chromeStorageOnChanged(_changes, area) {
    // We store data with keys [settings-v1, ...] into the local storage. Only broadcast an event if
    // the object stored with the settings key has changed.
    // We only store settings in the sync area, so storage.sync changes must be settings changes.
    if (area == "sync") {
      await this.load();
      this.dispatchEvent("change");
    }
  },

  async load() {
    // NOTE(philc): If we change the schema of the settings object in a backwards-incompatible way,
    // then we can fetch the whole storage object here and migrate any old settings the user has to
    // the new schema.
    if (!this._chromeStorageListenerInstalled) {
      this._chromeStorageListenerInstalled = true;
      chrome.storage.onChanged.addListener((changes, area) =>
        this.chromeStorageOnChanged(changes, area)
      );
    }

    let result = await chrome.storage.sync.get(null); // Get every key.
    result = this.migrateSettingsIfNecessary(result);
    result["settingsVersion"] = Utils.getCurrentVersion();
    this._settings = Object.assign(globalThis.structuredClone(defaultOptions), result);
  },

  isLoaded() {
    return this._settings != null;
  },

  get(key) {
    if (!this.isLoaded()) {
      throw new Error(`Getting the setting ${key} before settings have been loaded.`);
    }
    return globalThis.structuredClone(this._settings[key]);
  },

  async set(key, value) {
    if (!this.isLoaded()) {
      throw new Error(`Writing the setting ${key} before settings have been loaded.`);
    }
    this._settings[key] = value;
    await this.setSettings(this._settings);
  },

  getSettings() {
    return globalThis.structuredClone(this._settings);
  },

  // Returns a settings object and performs any migrates required if the settings object is from an
  // older version of Vimium.
  migrateSettingsIfNecessary(settings) {
    // Prior to Vimium version 2.0.0:
    // - In chrome.storages.sync, the value of each setting was encoded as a JSON string using
    //   JSON.stringify. This was probably an artifact of originally using localStorage, but is no
    //   longer necessary now that chrome.storage exists and can store objects. Note that when
    //   exporting a backup of settings on the options page, the values were not encoded as JSON
    //   strings.
    // - We only stored the settingsVersion key in the JSON payload when a user exported a backup of
    //   their settings. It wasn't set when writing the settings to chrome.storage.sync.

    // NOTE(philc): We want to migrate settings which have JSON-encoded values. Based on the notes
    // above, that should mean we only need to migrate if the settings object is missing a
    // "settingsVersion" key.
    const shouldMigrate = settings["settingsVersion"] == null;
    if (!shouldMigrate) return settings;

    // Migration for v2.0.0: decode all values so that they're not JSON string encoded.
    const newSettings = {};
    for (const [k, v] of Object.entries(settings)) {
      // Most pre-2.0 settings were strings, but the global marks were stored as native values. See
      // #4323. So check the setting value's type before migrating.
      if (typeof v === "string") {
        newSettings[k] = JSON.parse(v);
      } else {
        newSettings[k] = v;
      }
    }
    // This key is no longer stored in our settings, but rather chrome.storage.session.
    delete newSettings.passNextKeyKeys;
    return newSettings;
  },

  async setSettings(settings) {
    settings = this.migrateSettingsIfNecessary(settings);
    settings["settingsVersion"] = Utils.getCurrentVersion();
    const result = this.pruneOutDefaultValues(settings);
    // If, after pruning, some keys were removed because their values are now equal to the default
    // values, then explicitly clear those from storage. Otherwise they will remain.
    // NOTE(philc): This kind of sharp edge is a reason to switch to storing the settings object as
    // one big object, rather than as top-level keys in chrome.storage. The tradeoff is that each
    // value in chrome-storage has a maximum size.
    const resultKeys = Object.keys(result);
    const removedKeys = Object.keys(settings).filter((key) => !resultKeys.includes(key));
    await chrome.storage.sync.remove(removedKeys);
    await chrome.storage.sync.set(result);
    await this.load();
  },

  // Returns a new object, removing the keys from `settings` which are equal to the default values
  // for those keys.
  pruneOutDefaultValues(settings) {
    const clonedSettings = globalThis.structuredClone(settings);
    for (const [k, v] of Object.entries(settings)) {
      if (JSON.stringify(v) == JSON.stringify(defaultOptions[k])) {
        delete clonedSettings[k];
      }
    }
    return clonedSettings;
  },

  // Used only by tests.
  async clear() {
    this._settings = null;
    await chrome.storage.sync.clear();
  },
};

Object.assign(Settings, EventDispatcher);

globalThis.Settings = Settings;

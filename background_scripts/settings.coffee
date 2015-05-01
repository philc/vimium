#
# Used by all parts of Vimium to manipulate localStorage.
#

root = exports ? window
root.Settings = Settings =
  get: (key) ->
    if (key of localStorage) then JSON.parse(localStorage[key]) else @defaults[key]

  set: (key, value) ->
    # Don't store the value if it is equal to the default, so we can change the defaults in the future
    if (value == @defaults[key])
      @clear(key)
    else
      jsonValue = JSON.stringify value
      localStorage[key] = jsonValue
      Sync.set key, jsonValue

  clear: (key) ->
    if @has key
      delete localStorage[key]
    Sync.clear key

  has: (key) -> key of localStorage

  # For settings which require action when their value changes, add hooks here called from
  # options/options.coffee (when the options page is saved), and from background_scripts/sync.coffee (when an
  # update propagates from chrome.storage.sync).
  postUpdateHooks:
    keyMappings: (value) ->
      root.Commands.clearKeyMappingsAndSetDefaults()
      root.Commands.parseCustomKeyMappings value
      root.refreshCompletionKeysAfterMappingSave()

    searchEngines: (value) ->
      root.CustomSearchEngineCompleter.parseSearchEngines value

    exclusionRules: (value) ->
      root.Exclusions.postUpdateHook value

  # postUpdateHooks convenience wrapper
  performPostUpdateHook: (key, value) ->
    @postUpdateHooks[key] value if @postUpdateHooks[key]

  # options.coffee and options.html only handle booleans and strings; therefore all defaults must be booleans
  # or strings
  defaults:
    scrollStepSize: 60
    smoothScroll: true
    keyMappings: "# Insert your preferred key mappings here."
    linkHintCharacters: "sadfjklewcmpgh"
    linkHintNumbers: "0123456789"
    filterLinkHints: false
    hideHud: false
    userDefinedLinkHintCss:
      """
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
      }
      """
    # Default exclusion rules.
    exclusionRules:
      [
        # Disable Vimium on Gmail.
        { pattern: "http*://mail.google.com/*", passKeys: "" }
      ]

    # NOTE: If a page contains both a single angle-bracket link and a double angle-bracket link, then in
    # most cases the single bracket link will be "prev/next page" and the double bracket link will be
    # "first/last page", so we put the single bracket first in the pattern string so that it gets searched
    # for first.

    # "\bprev\b,\bprevious\b,\bback\b,<,←,«,≪,<<"
    previousPatterns: "prev,previous,back,<,\u2190,\xab,\u226a,<<"
    # "\bnext\b,\bmore\b,>,→,»,≫,>>"
    nextPatterns: "next,more,>,\u2192,\xbb,\u226b,>>"
    # default/fall back search engine
    searchUrl: "http://www.google.com/search?q="
    # put in an example search engine
    searchEngines: "w: http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s wikipedia"
    newTabUrl: "chrome://newtab"
    grabBackFocus: false

    settingsVersion: Utils.getCurrentVersion()


# We use settingsVersion to coordinate any necessary schema changes.
if Utils.compareVersions("1.42", Settings.get("settingsVersion")) != -1
  Settings.set("scrollStepSize", parseFloat Settings.get("scrollStepSize"))
Settings.set("settingsVersion", Utils.getCurrentVersion())

# Migration (after 1.49, 2015/2/1).
# Legacy setting: findModeRawQuery (a string).
# New setting: findModeRawQueryList (a list of strings), now stored in chrome.storage.local (not localStorage).
chrome.storage.local.get "findModeRawQueryList", (items) ->
  unless chrome.runtime.lastError or items.findModeRawQueryList
    rawQuery = Settings.get "findModeRawQuery"
    chrome.storage.local.set findModeRawQueryList: (if rawQuery then [ rawQuery ] else [])


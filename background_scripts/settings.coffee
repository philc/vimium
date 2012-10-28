#
# Used by everyone to manipulate localStorage.
#

root = exports ? window
root.Settings = Settings =
  get: (key) ->
    if (key of localStorage) then JSON.parse(localStorage[key]) else @defaults[key]

  set: (key, value) ->
    # don't store the value if it is equal to the default, so we can change the defaults in the future
    # warning: this test is always false for settings with numeric default values (such as scrollStepSize)
    if ( value == @defaults[key] )
      return @clear(key)
    # don't update the key/value if it's unchanged; thereby suppressing unnecessary calls to chrome.storage
    valueJSON = JSON.stringify value
    if localStorage[key] == valueJSON
      return localStorage[key]
    # we have a new value: so update chrome.storage and localStorage
    root.Sync.set key, valueJSON
    localStorage[key] = valueJSON

  clear: (key) ->
    if @has key
      root.Sync.clear key
      delete localStorage[key]

  has: (key) -> key of localStorage

  # the postUpdateHooks handler below is called each time an option changes:
  #    either from options/options.coffee          (when the options page is saved)
  #        or from background_scripts/sync.coffee  (when an update propagates from chrome.storage)
  # 
  # NOTE:
  # this has been refactored and renamed from ../options/options.coffee(postSaveHooks):
  #   - refactored because it is now also called from background_scripts/sync.coffee
  #   - renamed because it is no longer associated only with "Save" operations
  #
  postUpdateHooks:
    keyMappings: (value) ->
      root.Commands.clearKeyMappingsAndSetDefaults()
      root.Commands.parseCustomKeyMappings value
      root.refreshCompletionKeysAfterMappingSave()
  
  # postUpdateHooks convenience wrapper
  doPostUpdateHook: (key, value) ->
    if @postUpdateHooks[key]
      @postUpdateHooks[key] value 

  defaults:
    scrollStepSize: 60
    linkHintCharacters: "sadfjklewcmpgh"
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
    excludedUrls:
      """
      http*://mail.google.com/*
      http*://www.google.com/reader/*
      """
    # NOTE : If a page contains both a single angle-bracket link and a double angle-bracket link, then in
    # most cases the single bracket link will be "prev/next page" and the double bracket link will be
    # "first/last page", so we put the single bracket first in the pattern string so that it gets searched
    # for first.

    # "\bprev\b,\bprevious\b,\bback\b,<,←,«,≪,<<"
    previousPatterns: "prev,previous,back,<,\u2190,\xab,\u226a,<<"
    # "\bnext\b,\bmore\b,>,→,»,≫,>>"
    nextPatterns: "next,more,>,\u2192,\xbb,\u226b,>>"
    # default/fall back search engine
    searchUrl: "http://www.google.com/search?q="

# Initialization code.
# We use this parameter to coordinate any necessary schema changes.
Settings.set("settingsVersion", Utils.getCurrentVersion())

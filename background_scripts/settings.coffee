#
# Used by everyone to manipulate localStorage.
#

root = exports ? window
root.Settings = Settings =
  get: (key) ->
    if (key of localStorage) then JSON.parse(localStorage[key]) else @defaults[key]

  set: (key, value) ->
    # don't store the value if it is equal to the default, so we can change the defaults in the future
    # warning: this test never matches for settings with numeric default values
    console.log "TEST: #{key} " + typeof(value) + " " + typeof(@defaults[key]) + " " + @defaults[key]
    if ( value == @defaults[key] )
      console.log("Settings clear key: #{key} has default value") if key of localStorage
      return @clear(key)
    # don't update the key/value if it's unchanged; this prevents unnecessary
    # updates and unnecessary calls to synced storage
    valueJSON = JSON.stringify value
    if localStorage[key] == valueJSON
      console.log("Settings skip update: #{key} unchanged")
      return localStorage[key]
    # we have a new value: so update localStorage and synced storage
    console.log "Settings updating: #{key}"
    localStorage[key] = valueJSON
    root.Sync.set key, valueJSON

  clear: (key) ->
    if @has key
      root.Sync.clear key
      delete localStorage[key]

  has: (key) -> key of localStorage

  # the relevant postUpdateHooks handler is called each time a settings value
  # changes:
  #    either from options/options.coffee          (when the settings page is saved)
  #        or from background_scripts/sync.coffee  (when an update propagates from synced storage)
  # 
  # NOTE: this has been refactored and renamed from postSaveHooks in
  # options.coffee:
  #   - refactored because it is now also called from background_scripts/sync.coffee
  #   - renamed because it is no longer associated only with "Save" operations
  #
  postUpdateHooks:
    keyMappings: (value) ->
      console.log "postUpdateHooks[keyMappings]: #{value}"
      root.Commands.clearKeyMappingsAndSetDefaults()
      root.Commands.parseCustomKeyMappings value
      root.refreshCompletionKeysAfterMappingSave()
  
  # postUpdateHooks wrapper
  doPostUpdateHooks: (key, value) ->
    if @postUpdateHooks[key]
       console.log "running postUpdateHooks[#{key}]"
       @postUpdateHooks[key] value if @postUpdateHooks[key]

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

#
# Used by everyone to manipulate localStorage.
#

root = exports ? window
root.Settings = Settings =
  get: (key) ->
    if (key of localStorage) then JSON.parse(localStorage[key]) else @defaults[key]

  set: (key, value) ->
    # don't store the value if it is equal to the default, so we can change the defaults in the future
    if (value == @defaults[key])
      @clear(key)
    else
      localStorage[key] = JSON.stringify(value)

  clear: (key) -> delete localStorage[key]

  has: (key) -> key of localStorage

  defaults:
    scrollStepSize: 60
    linkHintCharacters: "sadfjklewcmpgh"
    filterLinkHints: false
    hideHud: false
    userDefinedLinkHintCss:
      """
      div > .vimiumHintMarker {
      /* linkhint boxes */
      background-color: yellow;
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

# Initialization code.
# settingsVersion was introduced in v1.31, and is used to coordinate data migration. We do not use
# previousVersion as it is used to coordinate the display of the upgrade message, and is not updated
# early enough when the extension loads.
# 1.31 was also the version where we converted all localStorage values to JSON.
if (!Settings.has("settingsVersion"))
  for key of localStorage
    # filterLinkHints' checkbox state used to be stored as a string
    if (key == "filterLinkHints")
      localStorage[key] = if (localStorage[key] == "true") then true else false
    else
      localStorage[key] = JSON.stringify(localStorage[key])
  Settings.set("settingsVersion", Utils.getCurrentVersion())

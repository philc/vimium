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

  # options/options.(coffee|html) only handle booleans and strings; therefore
  # all defaults must be booleans or strings
  defaults:
    scrollStepSize: 60
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
    excludedUrls:
      """
      http*://mail.google.com/*
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

    settingsVersion: Utils.getCurrentVersion()

# We use settingsVersion to coordinate any necessary schema changes.
if Utils.compareVersions("1.42", Settings.get("settingsVersion")) != -1
  Settings.set("scrollStepSize", parseFloat Settings.get("scrollStepSize"))
Settings.set("settingsVersion", Utils.getCurrentVersion())

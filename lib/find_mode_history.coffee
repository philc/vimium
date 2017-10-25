# NOTE(mrmr1993): This is under lib/ since it is used by both content scripts and iframes from pages/.
# This implements find-mode query history (using the "findModeRawQueryList" setting) as a list of raw queries,
# most recent first.
FindModeHistory =
  storage: chrome?.storage.local # Guard against chrome being undefined (in the HUD iframe).
  key: "findModeRawQueryList"
  max: 50
  rawQueryList: null

  init: ->
    @isIncognitoMode = chrome?.extension.inIncognitoContext

    return unless @isIncognitoMode? # chrome is undefined in the HUD iframe during tests, so we do nothing.

    unless @rawQueryList
      @rawQueryList = [] # Prevent repeated initialization.
      @key = "findModeRawQueryListIncognito" if @isIncognitoMode
      @storage.get @key, (items) =>
        unless chrome.runtime.lastError
          @rawQueryList = items[@key] if items[@key]
          if @isIncognitoMode and not items[@key]
            # This is the first incognito tab, so we need to initialize the incognito-mode query history.
            @storage.get "findModeRawQueryList", (items) =>
              unless chrome.runtime.lastError
                @rawQueryList = items.findModeRawQueryList
                @storage.set findModeRawQueryListIncognito: @rawQueryList

    chrome.storage.onChanged.addListener (changes, area) =>
      @rawQueryList = changes[@key].newValue if changes[@key]

  getQuery: (index = 0) ->
    @rawQueryList[index] or ""

  saveQuery: (query) ->
    if 0 < query.length
      @rawQueryList = @refreshRawQueryList query, @rawQueryList
      newSetting = {}; newSetting[@key] = @rawQueryList
      @storage.set newSetting
      # If there are any active incognito-mode tabs, then propagte this query to those tabs too.
      unless @isIncognitoMode
        @storage.get "findModeRawQueryListIncognito", (items) =>
          if not chrome.runtime.lastError and items.findModeRawQueryListIncognito
            @storage.set
              findModeRawQueryListIncognito: @refreshRawQueryList query, items.findModeRawQueryListIncognito

  refreshRawQueryList: (query, rawQueryList) ->
    ([ query ].concat rawQueryList.filter (q) => q != query)[0..@max]

root = exports ? (window.root ?= {})
root.FindModeHistory = FindModeHistory
extend window, root unless exports?

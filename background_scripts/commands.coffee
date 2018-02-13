Commands =
  availableCommands: {}
  keyToCommandRegistry: null
  mapKeyRegistry: null

  init: ->
    for own command, [description, options] of commandDescriptions
      @availableCommands[command] = extend (options ? {}), description: description

    Settings.postUpdateHooks["keyMappings"] = @loadKeyMappings.bind this
    @loadKeyMappings Settings.get "keyMappings"

  loadKeyMappings: (customKeyMappings) ->
    @keyToCommandRegistry = {}
    @mapKeyRegistry = {}

    configLines = ("map #{key} #{command}" for own key, command of defaultKeyMappings)
    configLines.push BgUtils.parseLines(customKeyMappings)...
    seen = {}
    unmapAll = false
    for line in configLines.reverse()
      tokens = line.split /\s+/
      switch tokens[0].toLowerCase()
        when "map"
          if 3 <= tokens.length and not unmapAll
            [_, key, command, optionList...] = tokens
            if not seen[key] and registryEntry = @availableCommands[command]
              seen[key] = true
              keySequence = @parseKeySequence key
              options = @parseCommandOptions command, optionList
              @keyToCommandRegistry[key] = extend {keySequence, command, options, optionList}, @availableCommands[command]
        when "unmap"
          if tokens.length == 2
            seen[tokens[1]] = true
        when "unmapall"
          unmapAll = true
        when "mapkey"
          if tokens.length == 3
            fromChar = @parseKeySequence tokens[1]
            toChar = @parseKeySequence tokens[2]
            @mapKeyRegistry[fromChar[0]] ?= toChar[0] if fromChar.length == toChar.length == 1

    chrome.storage.local.set mapKeyRegistry: @mapKeyRegistry
    @installKeyStateMapping()
    @prepareHelpPageData()

    # Push the key mapping for passNextKey into Settings so that it's available in the front end for insert
    # mode.  We exclude single-key mappings (that is, printable keys) because when users press printable keys
    # in insert mode they expect the character to be input, not to be droppped into some special Vimium
    # mode.
    Settings.set "passNextKeyKeys",
      (key for own key of @keyToCommandRegistry when @keyToCommandRegistry[key].command == "passNextKey" and 1 < key.length)

  # Lower-case the appropriate portions of named keys.
  #
  # A key name is one of three forms exemplified by <c-a> <left> or <c-f12>
  # (prefixed normal key, named key, or prefixed named key). Internally, for
  # simplicity, we would like prefixes and key names to be lowercase, though
  # humans may prefer other forms <Left> or <C-a>.
  # On the other hand, <c-a> and <c-A> are different named keys - for one of
  # them you have to press "shift" as well.
  # We sort modifiers here to match the order used in keyboard_utils.coffee.
  # The return value is a sequence of keys: e.g. "<Space><c-A>b" -> ["<space>", "<c-A>", "b"].
  parseKeySequence: do ->
    modifier = "(?:[acm]-)"                             # E.g. "a-", "c-", "m-".
    namedKey = "(?:[a-z][a-z0-9]+)"                     # E.g. "left" or "f12" (always two characters or more).
    modifiedKey = "(?:#{modifier}+(?:.|#{namedKey}))"   # E.g. "c-*" or "c-left".
    specialKeyRegexp = new RegExp "^<(#{namedKey}|#{modifiedKey})>(.*)", "i"
    (key) ->
      if key.length == 0
        []
      # Parse "<c-a>bcd" as "<c-a>" and "bcd".
      else if 0 == key.search specialKeyRegexp
        [modifiers..., keyChar] = RegExp.$1.split "-"
        keyChar = keyChar.toLowerCase() unless keyChar.length == 1
        modifiers = (modifier.toLowerCase() for modifier in modifiers)
        modifiers.sort()
        ["<#{[modifiers..., keyChar].join '-'}>", @parseKeySequence(RegExp.$2)...]
      else
        [key[0], @parseKeySequence(key[1..])...]

  # Command options follow command mappings, and are of one of two forms:
  #   key=value     - a value
  #   key           - a flag
  parseCommandOptions: (command, optionList) ->
    options = {}
    for option in optionList
      parse = option.split "=", 2
      options[parse[0]] = if parse.length == 1 then true else parse[1]

    # We parse any `count` option immediately (to avoid having to parse it repeatedly later).
    if "count" of options
      options.count = parseInt options.count
      delete options.count if isNaN(options.count) or @availableCommands[command].noRepeat

    options

  # This generates and installs a nested key-to-command mapping structure. There is an example in
  # mode_key_handler.coffee.
  installKeyStateMapping: ->
    keyStateMapping = {}
    for own keys, registryEntry of @keyToCommandRegistry
      currentMapping = keyStateMapping
      for key, index in registryEntry.keySequence
        if currentMapping[key]?.command
          # Do not overwrite existing command bindings, they take priority.  NOTE(smblott) This is the legacy
          # behaviour.
          break
        else if index < registryEntry.keySequence.length - 1
          currentMapping = currentMapping[key] ?= {}
        else
          currentMapping[key] = extend {}, registryEntry
          # We don't need these properties in the content scripts.
          delete currentMapping[key][prop] for prop in ["keySequence", "description"]
    chrome.storage.local.set normalModeKeyStateMapping: keyStateMapping
    # Inform `KeyboardUtils.isEscape()` whether `<c-[>` should be interpreted as `Escape` (which it is by
    # default).
    chrome.storage.local.set useVimLikeEscape: "<c-[>" not of keyStateMapping

  # Build the "helpPageData" data structure which the help page needs and place it in Chrome storage.
  prepareHelpPageData: ->
    commandToKey = {}
    for own key, registryEntry of @keyToCommandRegistry
      (commandToKey[registryEntry.command] ?= []).push key
    commandGroups = {}
    for own group, commands of @commandGroups
      commandGroups[group] = []
      for command in commands
        commandGroups[group].push
          command: command
          description: @availableCommands[command].description
          keys: commandToKey[command] ? []
          advanced: command in @advancedCommands
    chrome.storage.local.set helpPageData: commandGroups

  # An ordered listing of all available commands, grouped by type. This is the order they will
  # be shown in the help page.
  commandGroups:
    pageNavigation:
      ["scrollDown",
      "scrollUp",
      "scrollToTop",
      "scrollToBottom",
      "scrollPageDown",
      "scrollPageUp",
      "scrollFullPageDown",
      "scrollFullPageUp",
      "scrollLeft",
      "scrollRight",
      "scrollToLeft",
      "scrollToRight",
      "reload",
      "copyCurrentUrl",
      "openCopiedUrlInCurrentTab",
      "openCopiedUrlInNewTab",
      "goUp",
      "goToRoot",
      "enterInsertMode",
      "enterVisualMode",
      "enterVisualLineMode",
      "passNextKey",
      "focusInput",
      "LinkHints.activateMode",
      "LinkHints.activateModeToOpenInNewTab",
      "LinkHints.activateModeToOpenInNewForegroundTab",
      "LinkHints.activateModeWithQueue",
      "LinkHints.activateModeToDownloadLink",
      "LinkHints.activateModeToOpenIncognito",
      "LinkHints.activateModeToCopyLinkUrl",
      "goPrevious",
      "goNext",
      "nextFrame",
      "mainFrame",
      "Marks.activateCreateMode",
      "Marks.activateGotoMode"]
    vomnibarCommands:
      ["Vomnibar.activate",
      "Vomnibar.activateInNewTab",
      "Vomnibar.activateBookmarks",
      "Vomnibar.activateBookmarksInNewTab",
      "Vomnibar.activateTabSelection",
      "Vomnibar.activateEditUrl",
      "Vomnibar.activateEditUrlInNewTab"]
    findCommands: ["enterFindMode", "performFind", "performBackwardsFind"]
    historyNavigation:
      ["goBack", "goForward"]
    tabManipulation:
      ["createTab",
      "previousTab",
      "nextTab",
      "visitPreviousTab",
      "firstTab",
      "lastTab",
      "duplicateTab",
      "togglePinTab",
      "toggleMuteTab",
      "removeTab",
      "restoreTab",
      "moveTabToNewWindow",
      "closeTabsOnLeft","closeTabsOnRight",
      "closeOtherTabs",
      "moveTabLeft",
      "moveTabRight"]
    misc:
      ["showHelp",
      "toggleViewSource"]

  # Rarely used commands are not shown by default in the help dialog or in the README. The goal is to present
  # a focused, high-signal set of commands to the new and casual user. Only those truly hungry for more power
  # from Vimium will uncover these gems.
  advancedCommands: [
    "scrollToLeft",
    "scrollToRight",
    "moveTabToNewWindow",
    "goUp",
    "goToRoot",
    "LinkHints.activateModeWithQueue",
    "LinkHints.activateModeToDownloadLink",
    "Vomnibar.activateEditUrl",
    "Vomnibar.activateEditUrlInNewTab",
    "LinkHints.activateModeToOpenIncognito",
    "LinkHints.activateModeToCopyLinkUrl",
    "goNext",
    "goPrevious",
    "Marks.activateCreateMode",
    "Marks.activateGotoMode",
    "moveTabLeft",
    "moveTabRight",
    "closeTabsOnLeft",
    "closeTabsOnRight",
    "closeOtherTabs",
    "enterVisualLineMode",
    "toggleViewSource",
    "passNextKey"]

defaultKeyMappings =
  "?": "showHelp"
  "j": "scrollDown"
  "k": "scrollUp"
  "h": "scrollLeft"
  "l": "scrollRight"
  "gg": "scrollToTop"
  "G": "scrollToBottom"
  "zH": "scrollToLeft"
  "zL": "scrollToRight"
  "<c-e>": "scrollDown"
  "<c-y>": "scrollUp"

  "d": "scrollPageDown"
  "u": "scrollPageUp"
  "r": "reload"
  "gs": "toggleViewSource"

  "i": "enterInsertMode"
  "v": "enterVisualMode"
  "V": "enterVisualLineMode"

  "H": "goBack"
  "L": "goForward"
  "gu": "goUp"
  "gU": "goToRoot"

  "gi": "focusInput"

  "f": "LinkHints.activateMode"
  "F": "LinkHints.activateModeToOpenInNewTab"
  "<a-f>": "LinkHints.activateModeWithQueue"
  "yf": "LinkHints.activateModeToCopyLinkUrl"

  "/": "enterFindMode"
  "n": "performFind"
  "N": "performBackwardsFind"

  "[[": "goPrevious"
  "]]": "goNext"

  "yy": "copyCurrentUrl"

  "p": "openCopiedUrlInCurrentTab"
  "P": "openCopiedUrlInNewTab"

  "K": "nextTab"
  "J": "previousTab"
  "gt": "nextTab"
  "gT": "previousTab"
  "^": "visitPreviousTab"
  "<<": "moveTabLeft"
  ">>": "moveTabRight"
  "g0": "firstTab"
  "g$": "lastTab"

  "W": "moveTabToNewWindow"
  "t": "createTab"
  "yt": "duplicateTab"
  "x": "removeTab"
  "X": "restoreTab"

  "<a-p>": "togglePinTab"
  "<a-m>": "toggleMuteTab"

  "o": "Vomnibar.activate"
  "O": "Vomnibar.activateInNewTab"

  "T": "Vomnibar.activateTabSelection"

  "b": "Vomnibar.activateBookmarks"
  "B": "Vomnibar.activateBookmarksInNewTab"

  "ge": "Vomnibar.activateEditUrl"
  "gE": "Vomnibar.activateEditUrlInNewTab"

  "gf": "nextFrame"
  "gF": "mainFrame"

  "m": "Marks.activateCreateMode"
  "`": "Marks.activateGotoMode"


# This is a mapping of: commandIdentifier => [description, options].
# If the noRepeat and repeatLimit options are both specified, then noRepeat takes precedence.
commandDescriptions =
  # Navigating the current page
  showHelp: ["Show help", { topFrame: true, noRepeat: true }]
  scrollDown: ["Scroll down"]
  scrollUp: ["Scroll up"]
  scrollLeft: ["Scroll left"]
  scrollRight: ["Scroll right"]

  scrollToTop: ["Scroll to the top of the page"]
  scrollToBottom: ["Scroll to the bottom of the page", { noRepeat: true }]
  scrollToLeft: ["Scroll all the way to the left", { noRepeat: true }]
  scrollToRight: ["Scroll all the way to the right", { noRepeat: true }]

  scrollPageDown: ["Scroll a half page down"]
  scrollPageUp: ["Scroll a half page up"]
  scrollFullPageDown: ["Scroll a full page down"]
  scrollFullPageUp: ["Scroll a full page up"]

  reload: ["Reload the page", { background: true }]
  toggleViewSource: ["View page source", { noRepeat: true }]

  copyCurrentUrl: ["Copy the current URL to the clipboard", { noRepeat: true }]
  openCopiedUrlInCurrentTab: ["Open the clipboard's URL in the current tab", { noRepeat: true }]
  openCopiedUrlInNewTab: ["Open the clipboard's URL in a new tab", { repeatLimit: 20 }]

  enterInsertMode: ["Enter insert mode", { noRepeat: true }]
  passNextKey: ["Pass the next key to the page"]
  enterVisualMode: ["Enter visual mode", { noRepeat: true }]
  enterVisualLineMode: ["Enter visual line mode", { noRepeat: true }]

  focusInput: ["Focus the first text input on the page"]

  "LinkHints.activateMode": ["Open a link in the current tab"]
  "LinkHints.activateModeToOpenInNewTab": ["Open a link in a new tab"]
  "LinkHints.activateModeToOpenInNewForegroundTab": ["Open a link in a new tab & switch to it"]
  "LinkHints.activateModeWithQueue": ["Open multiple links in a new tab", { noRepeat: true }]
  "LinkHints.activateModeToOpenIncognito": ["Open a link in incognito window"]
  "LinkHints.activateModeToDownloadLink": ["Download link url"]
  "LinkHints.activateModeToCopyLinkUrl": ["Copy a link URL to the clipboard"]

  enterFindMode: ["Enter find mode", { noRepeat: true }]
  performFind: ["Cycle forward to the next find match"]
  performBackwardsFind: ["Cycle backward to the previous find match"]

  goPrevious: ["Follow the link labeled previous or <", { noRepeat: true }]
  goNext: ["Follow the link labeled next or >", { noRepeat: true }]

  # Navigating your history
  goBack: ["Go back in history"]
  goForward: ["Go forward in history"]

  # Navigating the URL hierarchy
  goUp: ["Go up the URL hierarchy"]
  goToRoot: ["Go to root of current URL hierarchy"]

  # Manipulating tabs
  nextTab: ["Go one tab right", { background: true }]
  previousTab: ["Go one tab left", { background: true }]
  visitPreviousTab: ["Go to previously-visited tab", { background: true }]
  firstTab: ["Go to the first tab", { background: true }]
  lastTab: ["Go to the last tab", { background: true }]

  createTab: ["Create new tab", { background: true, repeatLimit: 20 }]
  duplicateTab: ["Duplicate current tab", { background: true, repeatLimit: 20 }]
  removeTab: ["Close current tab", { background: true, repeatLimit: chrome.session?.MAX_SESSION_RESULTS ? 25 }]
  restoreTab: ["Restore closed tab", { background: true, repeatLimit: 20 }]

  moveTabToNewWindow: ["Move tab to new window", { background: true }]
  togglePinTab: ["Pin or unpin current tab", { background: true, noRepeat: true }]
  toggleMuteTab: ["Mute or unmute current tab", { background: true, noRepeat: true }]

  closeTabsOnLeft: ["Close tabs on the left", {background: true, noRepeat: true}]
  closeTabsOnRight: ["Close tabs on the right", {background: true, noRepeat: true}]
  closeOtherTabs: ["Close all other tabs", {background: true, noRepeat: true}]

  moveTabLeft: ["Move tab to the left", { background: true }]
  moveTabRight: ["Move tab to the right", { background: true }]

  "Vomnibar.activate": ["Open URL, bookmark or history entry", { topFrame: true }]
  "Vomnibar.activateInNewTab": ["Open URL, bookmark or history entry in a new tab", { topFrame: true }]
  "Vomnibar.activateTabSelection": ["Search through your open tabs", { topFrame: true }]
  "Vomnibar.activateBookmarks": ["Open a bookmark", { topFrame: true }]
  "Vomnibar.activateBookmarksInNewTab": ["Open a bookmark in a new tab", { topFrame: true }]
  "Vomnibar.activateEditUrl": ["Edit the current URL", { topFrame: true }]
  "Vomnibar.activateEditUrlInNewTab": ["Edit the current URL and open in a new tab", { topFrame: true }]

  nextFrame: ["Select the next frame on the page", { background: true }]
  mainFrame: ["Select the page's main/top frame", { topFrame: true, noRepeat: true }]

  "Marks.activateCreateMode": ["Create a new mark", { noRepeat: true }]
  "Marks.activateGotoMode": ["Go to a mark", { noRepeat: true }]

Commands.init()

root = exports ? window
root.Commands = Commands

Commands =
  init: ->
    for own command, description of commandDescriptions
      @addCommand(command, description[0], description[1])

  availableCommands: {}
  keyToCommandRegistry: {}

  # Registers a command, making it available to be optionally bound to a key.
  # options:
  #  - background: whether this command needs to be run against the background page.
  #  - passCountToFunction: true if this command should have any digits which were typed prior to the
  #    command passed to it. This is used to implement e.g. "closing of 3 tabs".
  addCommand: (command, description, options) ->
    if command of @availableCommands
      logMessage? "#{command} is already defined! Check commands.coffee for duplicates."
      return

    options ||= {}
    @availableCommands[command] =
      description: description
      isBackgroundCommand: options.background
      passCountToFunction: options.passCountToFunction
      noRepeat: options.noRepeat
      repeatLimit: options.repeatLimit

  mapKeyToCommand: ({ key, command, options }) ->
    unless @availableCommands[command]
      logMessage? "#{command} doesn't exist!"
      return

    options ?= {}
    @keyToCommandRegistry[key] = extend { command, options }, @availableCommands[command]

  # Lower-case the appropriate portions of named keys.
  #
  # A key name is one of three forms exemplified by <c-a> <left> or <c-f12>
  # (prefixed normal key, named key, or prefixed named key). Internally, for
  # simplicity, we would like prefixes and key names to be lowercase, though
  # humans may prefer other forms <Left> or <C-a>.
  # On the other hand, <c-a> and <c-A> are different named keys - for one of
  # them you have to press "shift" as well.
  normalizeKey: (key) ->
    key.replace(/<[acm]-/ig, (match) -> match.toLowerCase())
       .replace(/<([acm]-)?([a-zA-Z0-9]{2,5})>/g, (match, optionalPrefix, keyName) ->
          "<" + (if optionalPrefix then optionalPrefix else "") + keyName.toLowerCase() + ">")
       .replace /<space>/ig, " "

  parseCustomKeyMappings: (customKeyMappings) ->
    for line in customKeyMappings.split "\n"
      unless  line[0] == "\"" or line[0] == "#"
        tokens = line.replace(/\s+$/, "").split /\s+/
        switch tokens[0]
          when "map"
            [ _, key, command, optionList... ] = tokens
            if command? and @availableCommands[command]
              key = @normalizeKey key
              logMessage? "Mapping #{key} to #{command}"
              @mapKeyToCommand { key, command, options: @parseCommandOptions command, optionList }

          when "unmap"
            if tokens.length == 2
              key = @normalizeKey tokens[1]
              logMessage? "Unmapping #{key}"
              delete @keyToCommandRegistry[key]

          when "unmapAll"
            @keyToCommandRegistry = {}

    # Push the key mapping for passNextKey into Settings so that it's available in the front end for insert
    # mode.  We exclude single-key mappings (that is, printable keys) because when users press printable keys
    # in insert mode they expect the character to be input, not to be droppped into some special Vimium
    # mode.
    Settings.set "passNextKeyKeys",
      (key for own key of @keyToCommandRegistry when @keyToCommandRegistry[key].command == "passNextKey" and 1 < key.length)

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

  clearKeyMappingsAndSetDefaults: ->
    @keyToCommandRegistry = {}
    @mapKeyToCommand { key, command } for own key, command of defaultKeyMappings

  # Keys are either literal characters, or "named" - for example <a-b> (alt+b), <left> (left arrow) or <f12>
  # This regular expression captures two groups: the first is a named key, the second is the remainder of the
  # string.
  namedKeyRegex: /^(<(?:[amc]-.|(?:[amc]-)?[a-z0-9]{2,5})>)(.*)$/

  generateKeyStateStructure: ->
    keyMapping = {}
    for own keys, registryEntry of @keyToCommandRegistry
      currentMapping = keyMapping
      while 0 < keys.length
        [key, rest] = if 0 == keys.search @namedKeyRegex then [RegExp.$1, RegExp.$2] else [keys[0], keys.slice(1)]
        if 0 < rest.length
          currentMapping[key] ?= {}
          currentMapping = currentMapping[key]
        else
          currentMapping[key] = registryEntry
        keys = rest
    chrome.storage.local.set normalModeKeyStateMapping: keyMapping

  # An ordered listing of all available commands, grouped by type. This is the order they will
  # be shown in the help page.
  commandGroups:
    pageNavigation:
      ["scrollDown",
      "scrollUp",
      "scrollLeft",
      "scrollRight",
      "scrollToTop",
      "scrollToBottom",
      "scrollToLeft",
      "scrollToRight",
      "scrollPageDown",
      "scrollPageUp",
      "scrollFullPageUp",
      "scrollFullPageDown",
      "reload",
      "toggleViewSource",
      "copyCurrentUrl",
      "LinkHints.activateModeToCopyLinkUrl",
      "openCopiedUrlInCurrentTab",
      "openCopiedUrlInNewTab",
      "goUp",
      "goToRoot",
      "enterInsertMode",
      "passNextKey",
      "enterVisualMode",
      "enterVisualLineMode",
      "focusInput",
      "LinkHints.activateMode",
      "LinkHints.activateModeToOpenInNewTab",
      "LinkHints.activateModeToOpenInNewForegroundTab",
      "LinkHints.activateModeWithQueue",
      "LinkHints.activateModeToDownloadLink",
      "LinkHints.activateModeToOpenIncognito",
      "goPrevious",
      "goNext",
      "nextFrame",
      "mainFrame",
      "Marks.activateCreateMode",
      "Marks.activateGotoMode"]
    vomnibarCommands:
      ["Vomnibar.activate",
      "Vomnibar.activateInNewTab",
      "Vomnibar.activateTabSelection",
      "Vomnibar.activateBookmarks",
      "Vomnibar.activateBookmarksInNewTab",
      "Vomnibar.activateEditUrl",
      "Vomnibar.activateEditUrlInNewTab"]
    findCommands: ["enterFindMode", "performFind", "performBackwardsFind"]
    historyNavigation:
      ["goBack", "goForward"]
    tabManipulation:
      ["nextTab",
      "previousTab",
      "visitPreviousTab",
      "firstTab",
      "lastTab",
      "createTab",
      "duplicateTab",
      "removeTab",
      "restoreTab",
      "moveTabToNewWindow",
      "togglePinTab",
      "closeTabsOnLeft","closeTabsOnRight",
      "closeOtherTabs",
      "moveTabLeft",
      "moveTabRight"]
    misc:
      ["showHelp"]

  # Rarely used commands are not shown by default in the help dialog or in the README. The goal is to present
  # a focused, high-signal set of commands to the new and casual user. Only those truly hungry for more power
  # from Vimium will uncover these gems.
  advancedCommands: [
    "scrollToLeft",
    "scrollToRight",
    "moveTabToNewWindow",
    "goUp",
    "goToRoot",
    "focusInput",
    "LinkHints.activateModeWithQueue",
    "LinkHints.activateModeToDownloadLink",
    "Vomnibar.activateEditUrl",
    "Vomnibar.activateEditUrlInNewTab",
    "LinkHints.activateModeToOpenIncognito",
    "goNext",
    "goPrevious",
    "Marks.activateCreateMode",
    "Marks.activateGotoMode",
    "moveTabLeft",
    "moveTabRight",
    "closeTabsOnLeft",
    "closeTabsOnRight",
    "closeOtherTabs",
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

  "f":     "LinkHints.activateMode"
  "F":     "LinkHints.activateModeToOpenInNewTab"
  "<a-f>": "LinkHints.activateModeWithQueue"

  "/": "enterFindMode"
  "n": "performFind"
  "N": "performBackwardsFind"

  "[[": "goPrevious"
  "]]": "goNext"

  "yy": "copyCurrentUrl"
  "yf": "LinkHints.activateModeToCopyLinkUrl"

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
  showHelp: ["Show help", { background: true }]
  scrollDown: ["Scroll down", { passCountToFunction: true }]
  scrollUp: ["Scroll up", { passCountToFunction: true }]
  scrollLeft: ["Scroll left", { passCountToFunction: true }]
  scrollRight: ["Scroll right", { passCountToFunction: true }]

  scrollToTop: ["Scroll to the top of the page", { passCountToFunction: true }]
  scrollToBottom: ["Scroll to the bottom of the page", { noRepeat: true }]
  scrollToLeft: ["Scroll all the way to the left", { noRepeat: true }]
  scrollToRight: ["Scroll all the way to the right", { noRepeat: true }]

  scrollPageDown: ["Scroll a page down", { passCountToFunction: true }]
  scrollPageUp: ["Scroll a page up", { passCountToFunction: true }]
  scrollFullPageDown: ["Scroll a full page down", { passCountToFunction: true }]
  scrollFullPageUp: ["Scroll a full page up", { passCountToFunction: true }]

  reload: ["Reload the page", { noRepeat: true }]
  toggleViewSource: ["View page source", { noRepeat: true }]

  copyCurrentUrl: ["Copy the current URL to the clipboard", { noRepeat: true }]
  "LinkHints.activateModeToCopyLinkUrl": ["Copy a link URL to the clipboard", { passCountToFunction: true }]
  openCopiedUrlInCurrentTab: ["Open the clipboard's URL in the current tab", { background: true }]
  openCopiedUrlInNewTab: ["Open the clipboard's URL in a new tab", { background: true, repeatLimit: 20 }]

  enterInsertMode: ["Enter insert mode", { noRepeat: true }]
  passNextKey: ["Pass the next key to Chrome", { passCountToFunction: true }]
  enterVisualMode: ["Enter visual mode", { noRepeat: true }]
  enterVisualLineMode: ["Enter visual line mode", { noRepeat: true }]

  focusInput: ["Focus the first text box on the page. Cycle between them using tab",
    { passCountToFunction: true }]

  "LinkHints.activateMode": ["Open a link in the current tab", { passCountToFunction: true }]
  "LinkHints.activateModeToOpenInNewTab": ["Open a link in a new tab", { passCountToFunction: true }]
  "LinkHints.activateModeToOpenInNewForegroundTab": ["Open a link in a new tab & switch to it", { passCountToFunction: true }]
  "LinkHints.activateModeWithQueue": ["Open multiple links in a new tab", { noRepeat: true }]
  "LinkHints.activateModeToOpenIncognito": ["Open a link in incognito window", { passCountToFunction: true }]
  "LinkHints.activateModeToDownloadLink": ["Download link url", { passCountToFunction: true }]

  enterFindMode: ["Enter find mode", { noRepeat: true }]
  performFind: ["Cycle forward to the next find match"]
  performBackwardsFind: ["Cycle backward to the previous find match"]

  goPrevious: ["Follow the link labeled previous or <", { noRepeat: true }]
  goNext: ["Follow the link labeled next or >", { noRepeat: true }]

  # Navigating your history
  goBack: ["Go back in history", { passCountToFunction: true }]
  goForward: ["Go forward in history", { passCountToFunction: true }]

  # Navigating the URL hierarchy
  goUp: ["Go up the URL hierarchy", { passCountToFunction: true }]
  goToRoot: ["Go to root of current URL hierarchy", { passCountToFunction: true }]

  # Manipulating tabs
  nextTab: ["Go one tab right", { background: true, passCountToFunction: true }]
  previousTab: ["Go one tab left", { background: true, passCountToFunction: true }]
  visitPreviousTab: ["Go to previously-visited tab", { background: true, passCountToFunction: true }]
  firstTab: ["Go to the first tab", { background: true, passCountToFunction: true }]
  lastTab: ["Go to the last tab", { background: true, passCountToFunction: true }]

  createTab: ["Create new tab", { background: true, repeatLimit: 20 }]
  duplicateTab: ["Duplicate current tab", { background: true, passCountToFunction: true, repeatLimit: 20 }]
  removeTab: ["Close current tab", { background: true, passCountToFunction: true, repeatLimit:
    # Require confirmation to remove more tabs than we can restore.
    (if chrome.session then chrome.session.MAX_SESSION_RESULTS else 25) }]
  restoreTab: ["Restore closed tab", { background: true, repeatLimit: 20 }]

  moveTabToNewWindow: ["Move tab to new window", { background: true, passCountToFunction: true }]
  togglePinTab: ["Pin/unpin current tab", { background: true }]

  closeTabsOnLeft: ["Close tabs on the left", {background: true, noRepeat: true}]
  closeTabsOnRight: ["Close tabs on the right", {background: true, noRepeat: true}]
  closeOtherTabs: ["Close all other tabs", {background: true, noRepeat: true}]

  moveTabLeft: ["Move tab to the left", { background: true, passCountToFunction: true }]
  moveTabRight: ["Move tab to the right", { background: true, passCountToFunction: true  }]

  "Vomnibar.activate": ["Open URL, bookmark, or history entry", { background: true, noRepeat: true }]
  "Vomnibar.activateInNewTab": ["Open URL, bookmark, history entry, in a new tab", { background: true, noRepeat: true }]
  "Vomnibar.activateTabSelection": ["Search through your open tabs", { background: true, noRepeat: true }]
  "Vomnibar.activateBookmarks": ["Open a bookmark", { background: true, noRepeat: true }]
  "Vomnibar.activateBookmarksInNewTab": ["Open a bookmark in a new tab", { background: true, noRepeat: true }]
  "Vomnibar.activateEditUrl": ["Edit the current URL", { background: true, noRepeat: true }]
  "Vomnibar.activateEditUrlInNewTab": ["Edit the current URL and open in a new tab", { background: true, noRepeat: true }]

  nextFrame: ["Cycle forward to the next frame on the page", { background: true, passCountToFunction: true }]
  mainFrame: ["Select the tab's main/top frame", { background: true, noRepeat: true }]

  "Marks.activateCreateMode": ["Create a new mark", { noRepeat: true }]
  "Marks.activateGotoMode": ["Go to a mark", { noRepeat: true }]

Commands.init()

# Register postUpdateHook for keyMappings setting.
Settings.postUpdateHooks["keyMappings"] = (value) ->
  Commands.clearKeyMappingsAndSetDefaults()
  Commands.parseCustomKeyMappings value
  Commands.generateKeyStateStructure()

root = exports ? window
root.Commands = Commands

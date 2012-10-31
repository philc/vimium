Commands =
  init: ->
    for command, description of commandDescriptions
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
      console.log(command, "is already defined! Check commands.coffee for duplicates.")
      return

    options ||= {}
    @availableCommands[command] =
      description: description
      isBackgroundCommand: options.background
      passCountToFunction: options.passCountToFunction

  mapKeyToCommand: (key, command) ->
    unless @availableCommands[command]
      console.log(command, "doesn't exist!")
      return

    @keyToCommandRegistry[key] =
      command: command
      isBackgroundCommand: @availableCommands[command].isBackgroundCommand
      passCountToFunction: @availableCommands[command].passCountToFunction

  unmapKey: (key) -> delete @keyToCommandRegistry[key]

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

  parseCustomKeyMappings: (customKeyMappings) ->
    lines = customKeyMappings.split("\n")

    for line in lines
      continue if (line[0] == "\"" || line[0] == "#")
      splitLine = line.split(/\s+/)

      lineCommand = splitLine[0]

      if (lineCommand == "map")
        continue if (splitLine.length != 3)
        key = @normalizeKey(splitLine[1])
        vimiumCommand = splitLine[2]

        continue unless @availableCommands[vimiumCommand]

        console.log("Mapping", key, "to", vimiumCommand)
        @mapKeyToCommand(key, vimiumCommand)
      else if (lineCommand == "unmap")
        continue if (splitLine.length != 2)

        key = @normalizeKey(splitLine[1])
        console.log("Unmapping", key)
        @unmapKey(key)
      else if (lineCommand == "unmapAll")
        @keyToCommandRegistry = {}

  clearKeyMappingsAndSetDefaults: ->
    @keyToCommandRegistry = {}

    for key of defaultKeyMappings
      @mapKeyToCommand(key, defaultKeyMappings[key])

  # An ordered listing of all available commands, grouped by type. This is the order they will
  # be shown in the help page.
  commandGroups:
    pageNavigation:
      ["scrollDown", "scrollUp", "scrollLeft", "scrollRight",
       "scrollToTop", "scrollToBottom", "scrollToLeft", "scrollToRight", "scrollPageDown",
       "scrollPageUp", "scrollFullPageUp", "scrollFullPageDown",
       "reload", "toggleViewSource", "copyCurrentUrl", "LinkHints.activateModeToCopyLinkUrl",
       "openCopiedUrlInCurrentTab", "openCopiedUrlInNewTab", "goUp",
       "enterInsertMode", "focusInput",
       "LinkHints.activateMode", "LinkHints.activateModeToOpenInNewTab", "LinkHints.activateModeWithQueue",
       "Vomnibar.activate", "Vomnibar.activateInNewTab", "Vomnibar.activateTabSelection",
       "Vomnibar.activateBookmarks", "Vomnibar.activateBookmarksInNewTab",
       "goPrevious", "goNext", "nextFrame", "Marks.activateCreateMode", "Marks.activateGotoMode"]
    findCommands: ["enterFindMode", "performFind", "performBackwardsFind"]
    historyNavigation:
      ["goBack", "goForward"]
    tabManipulation:
      ["nextTab", "previousTab", "firstTab", "lastTab", "createTab", "removeTab", "restoreTab"]
    misc:
      ["showHelp"]

  # Rarely used commands are not shown by default in the help dialog or in the README. The goal is to present
  # a focused, high-signal set of commands to the new and casual user. Only those truly hungry for more power
  # from Vimium will uncover these gems.
  advancedCommands: [
    "scrollToLeft", "scrollToRight",
    "goUp", "focusInput", "LinkHints.activateModeWithQueue",
    "goPrevious", "goNext", "Marks.activateCreateMode", "Marks.activateGotoMode"]

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

  "H": "goBack"
  "L": "goForward"
  "gu": "goUp"

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
  "g0": "firstTab"
  "g$": "lastTab"

  "t": "createTab"
  "x": "removeTab"
  "X": "restoreTab"

  "o": "Vomnibar.activate"
  "O": "Vomnibar.activateInNewTab"

  "T": "Vomnibar.activateTabSelection"

  "b": "Vomnibar.activateBookmarks"
  "B": "Vomnibar.activateBookmarksInNewTab"

  "gf": "nextFrame"

  "m": "Marks.activateCreateMode"
  "`": "Marks.activateGotoMode"


# This is a mapping of: commandIdentifier => [description, options].
commandDescriptions =
  # Navigating the current page
  showHelp: ["Show help", { background: true }]
  scrollDown: ["Scroll down"]
  scrollUp: ["Scroll up"]
  scrollLeft: ["Scroll left"]
  scrollRight: ["Scroll right"]
  scrollToTop: ["Scroll to the top of the page"]
  scrollToBottom: ["Scroll to the bottom of the page"]
  scrollToLeft: ["Scroll all the way to the left"]

  scrollToRight: ["Scroll all the way to the right"]
  scrollPageDown: ["Scroll a page down"]
  scrollPageUp: ["Scroll a page up"]
  scrollFullPageDown: ["Scroll a full page down"]
  scrollFullPageUp: ["Scroll a full page up"]

  reload: ["Reload the page"]
  toggleViewSource: ["View page source"]

  copyCurrentUrl: ["Copy the current URL to the clipboard"]
  'LinkHints.activateModeToCopyLinkUrl': ["Copy a link URL to the clipboard"]
  openCopiedUrlInCurrentTab: ["Open the clipboard's URL in the current tab", { background: true }]
  openCopiedUrlInNewTab: ["Open the clipboard's URL in a new tab", { background: true }]

  enterInsertMode: ["Enter insert mode"]

  focusInput: ["Focus the first (or n-th) text box on the page", { passCountToFunction: true }]

  'LinkHints.activateMode': ["Open a link in the current tab"]
  'LinkHints.activateModeToOpenInNewTab': ["Open a link in a new tab"]
  'LinkHints.activateModeWithQueue': ["Open multiple links in a new tab"]

  enterFindMode: ["Enter find mode"]
  performFind: ["Cycle forward to the next find match"]
  performBackwardsFind: ["Cycle backward to the previous find match"]

  goPrevious: ["Follow the link labeled previous or <"]
  goNext: ["Follow the link labeled next or >"]

  # Navigating your history
  goBack: ["Go back in history", { passCountToFunction: true }]
  goForward: ["Go forward in history", { passCountToFunction: true }]

  # Navigating the URL hierarchy
  goUp: ["Go up the URL hierarchy", { passCountToFunction: true }]

  # Manipulating tabs
  nextTab: ["Go one tab right", { background: true }]
  previousTab: ["Go one tab left", { background: true }]
  firstTab: ["Go to the first tab", { background: true }]
  lastTab: ["Go to the last tab", { background: true }]
  createTab: ["Create new tab", { background: true }]
  removeTab: ["Close current tab", { background: true }]
  restoreTab: ["Restore closed tab", { background: true }]

  "Vomnibar.activate": ["Open URL, bookmark, or history entry"]
  "Vomnibar.activateInNewTab": ["Open URL, bookmark, history entry, in a new tab"]
  "Vomnibar.activateTabSelection": ["Search through your open tabs"]
  "Vomnibar.activateBookmarks": ["Open a bookmark"]
  "Vomnibar.activateBookmarksInNewTab": ["Open a bookmark in a new tab"]

  nextFrame: ["Cycle forward to the next frame on the page", { background: true, passCountToFunction: true }]

  "Marks.activateCreateMode": ["Create a new mark"]
  "Marks.activateGotoMode": ["Go to a mark"]

Commands.init()

root = exports ? window
root.Commands = Commands

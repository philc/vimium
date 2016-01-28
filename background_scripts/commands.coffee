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
      noRepeat: options.noRepeat
      repeatLimit: options.repeatLimit

  mapKeyToCommand: ({ key, command, options }) ->
    unless @availableCommands[command]
      console.log command, "doesn't exist!"
      return

    options ?= []
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
            [ _, key, command, options... ] = tokens
            if command? and @availableCommands[command]
              key = @normalizeKey key
              console.log "Mapping", key, "to", command
              @mapKeyToCommand { key, command, options }

          when "unmap"
            if tokens.length == 2
              key = @normalizeKey tokens[1]
              console.log "Unmapping", key
              delete @keyToCommandRegistry[key]

          when "unmapAll"
            @keyToCommandRegistry = {}

  clearKeyMappingsAndSetDefaults: ->
    @keyToCommandRegistry = {}
    @mapKeyToCommand { key, command } for key, command of defaultKeyMappings

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
      "enterVisualMode",
      "enterVisualLineMode",
      # "enterEditMode",
      "focusInput",
      "LinkHints.activateMode",
      "LinkHints.activateModeToOpenInNewTab",
      "LinkHints.activateModeToOpenInNewForegroundTab",
      "LinkHints.activateModeWithQueue",
      "LinkHints.activateModeToDownloadLink",
      "LinkHints.activateModeToOpenIncognito",
      "LinkHints.activateModeForMenu",
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
    "closeOtherTabs"]

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
  # "gv": "enterEditMode"

  "H": "goBack"
  "L": "goForward"
  "gu": "goUp"
  "gU": "goToRoot"

  "gi": "focusInput"

  "f":     "LinkHints.activateMode"
  "F":     "LinkHints.activateModeToOpenInNewTab"
  "<a-f>": "LinkHints.activateModeWithQueue"
  "gm": "LinkHints.activateModeForMenu"

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
  scrollDown: ["Scroll down"]
  scrollUp: ["Scroll up"]
  scrollLeft: ["Scroll left"]
  scrollRight: ["Scroll right"]

  scrollToTop: ["Scroll to the top of the page", { noRepeat: true }]
  scrollToBottom: ["Scroll to the bottom of the page", { noRepeat: true }]
  scrollToLeft: ["Scroll all the way to the left", { noRepeat: true }]
  scrollToRight: ["Scroll all the way to the right", { noRepeat: true }]

  scrollPageDown: ["Scroll a page down"]
  scrollPageUp: ["Scroll a page up"]
  scrollFullPageDown: ["Scroll a full page down"]
  scrollFullPageUp: ["Scroll a full page up"]

  reload: ["Reload the page", { noRepeat: true }]
  toggleViewSource: ["View page source", { noRepeat: true }]

  copyCurrentUrl: ["Copy the current URL to the clipboard", { noRepeat: true }]
  "LinkHints.activateModeToCopyLinkUrl": ["Copy a link URL to the clipboard", { noRepeat: true }]
  openCopiedUrlInCurrentTab: ["Open the clipboard's URL in the current tab", { background: true }]
  openCopiedUrlInNewTab: ["Open the clipboard's URL in a new tab", { background: true, repeatLimit: 20 }]

  enterInsertMode: ["Enter insert mode", { noRepeat: true }]
  enterVisualMode: ["Enter visual mode", { noRepeat: true }]
  enterVisualLineMode: ["Enter visual line mode", { noRepeat: true }]
  # enterEditMode: ["Enter vim-like edit mode (not yet implemented)", { noRepeat: true }]

  focusInput: ["Focus the first text box on the page. Cycle between them using tab",
    { passCountToFunction: true }]

  "LinkHints.activateMode": ["Open a link in the current tab", { noRepeat: true }]
  "LinkHints.activateModeToOpenInNewTab": ["Open a link in a new tab", { noRepeat: true }]
  "LinkHints.activateModeToOpenInNewForegroundTab": ["Open a link in a new tab & switch to it", { noRepeat: true }]
  "LinkHints.activateModeWithQueue": ["Open multiple links in a new tab", { noRepeat: true }]
  "LinkHints.activateModeToOpenIncognito": ["Open a link in incognito window", { noRepeat: true }]
  "LinkHints.activateModeToDownloadLink": ["Download link url", { noRepeat: true }]
  "LinkHints.activateModeForMenu": ["Open a link's context menu", { noRepeat: true }]

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
  firstTab: ["Go to the first tab", { background: true, passCountToFunction: true }]
  lastTab: ["Go to the last tab", { background: true, passCountToFunction: true }]

  createTab: ["Create new tab", { background: true, repeatLimit: 20 }]
  duplicateTab: ["Duplicate current tab", { background: true, repeatLimit: 20 }]
  removeTab: ["Close current tab", { background: true, repeatLimit:
    # Require confirmation to remove more tabs than we can restore.
    (if chrome.session then chrome.session.MAX_SESSION_RESULTS else 25) }]
  restoreTab: ["Restore closed tab", { background: true, repeatLimit: 20 }]

  moveTabToNewWindow: ["Move tab to new window", { background: true }]
  togglePinTab: ["Pin/unpin current tab", { background: true }]

  closeTabsOnLeft: ["Close tabs on the left", {background: true, noRepeat: true}]
  closeTabsOnRight: ["Close tabs on the right", {background: true, noRepeat: true}]
  closeOtherTabs: ["Close all other tabs", {background: true, noRepeat: true}]

  moveTabLeft: ["Move tab to the left", { background: true, passCountToFunction: true }]
  moveTabRight: ["Move tab to the right", { background: true, passCountToFunction: true  }]

  "Vomnibar.activate": ["Open URL, bookmark, or history entry", { noRepeat: true }]
  "Vomnibar.activateInNewTab": ["Open URL, bookmark, history entry, in a new tab", { noRepeat: true }]
  "Vomnibar.activateTabSelection": ["Search through your open tabs", { noRepeat: true }]
  "Vomnibar.activateBookmarks": ["Open a bookmark", { noRepeat: true }]
  "Vomnibar.activateBookmarksInNewTab": ["Open a bookmark in a new tab", { noRepeat: true }]
  "Vomnibar.activateEditUrl": ["Edit the current URL", { noRepeat: true }]
  "Vomnibar.activateEditUrlInNewTab": ["Edit the current URL and open in a new tab", { noRepeat: true }]

  nextFrame: ["Cycle forward to the next frame on the page", { background: true, passCountToFunction: true }]
  mainFrame: ["Select the tab's main/top frame", { background: true, noRepeat: true }]

  "Marks.activateCreateMode": ["Create a new mark", { noRepeat: true }]
  "Marks.activateGotoMode": ["Go to a mark", { noRepeat: true }]

Commands.init()

# Register postUpdateHook for keyMappings setting.
Settings.postUpdateHooks["keyMappings"] = (value) ->
  Commands.clearKeyMappingsAndSetDefaults()
  Commands.parseCustomKeyMappings value
  refreshCompletionKeysAfterMappingSave()

root = exports ? window
root.Commands = Commands

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

  mapKeyToCommand: (key, command) ->
    unless @availableCommands[command]
      console.log(command, "doesn't exist!")
      return

    @keyToCommandRegistry[key] =
      command: command
      isBackgroundCommand: @availableCommands[command].isBackgroundCommand
      passCountToFunction: @availableCommands[command].passCountToFunction
      noRepeat: @availableCommands[command].noRepeat

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
       "openCopiedUrlInCurrentTab", "openCopiedUrlInNewTab", "goUp", "goToRoot",
       "enterInsertMode", "focusInput",
       "LinkHints.activateMode", "LinkHints.activateModeToOpenInNewTab", "LinkHints.activateModeWithQueue",
       "Vomnibar.activate", "Vomnibar.activateInNewTab", "Vomnibar.activateTabSelection",
       "Vomnibar.activateBookmarks", "Vomnibar.activateBookmarksInNewTab",
       "goPrevious", "goNext", "nextFrame", "Marks.activateCreateMode", "Marks.activateGotoMode"]
    findCommands: ["enterFindMode", "performFind", "performBackwardsFind"]
    historyNavigation:
      ["goBack", "goForward"]
    tabManipulation:
      ["nextTab", "previousTab", "firstTab", "lastTab", "createTab", "duplicateTab", "removeTab", "restoreTab", "moveTabToNewWindow"]
    misc:
      ["showHelp"]

  # Rarely used commands are not shown by default in the help dialog or in the README. The goal is to present
  # a focused, high-signal set of commands to the new and casual user. Only those truly hungry for more power
  # from Vimium will uncover these gems.
  advancedCommands: [
    "scrollToLeft", "scrollToRight", "moveTabToNewWindow",
    "goUp", "goToRoot", "focusInput", "LinkHints.activateModeWithQueue",
    "LinkHints.activateModeToOpenIncognito", "goNext", "goPrevious", "Marks.activateCreateMode",
    "Marks.activateGotoMode"]

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
  "g0": "firstTab"
  "g$": "lastTab"

  "W": "moveTabToNewWindow"
  "t": "createTab"
  "yt": "duplicateTab"
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

i18n = chrome.i18n.getMessage

# This is a mapping of: commandIdentifier => [description, options].
commandDescriptions =
  # Navigating the current page
  showHelp: [i18n("show_help"), { background: true }]
  scrollDown: [i18n("scroll_down")]
  scrollUp: [i18n("scroll_up")]
  scrollLeft: [i18n("scroll_left")]
  scrollRight: [i18n("scroll_right")]
  scrollToTop: [i18n("scroll_to_top")]
  scrollToBottom: [i18n("scroll_to_bottom")]
  scrollToLeft: [i18n("scroll_to_left")]

  scrollToRight: [i18n("scroll_to_right")]
  scrollPageDown: [i18n("scroll_page_down")]
  scrollPageUp: [i18n("scroll_page_up")]
  scrollFullPageDown: [i18n("scroll_full_page_down")]
  scrollFullPageUp: [i18n("scroll_full_page_up")]

  reload: [i18n("reload")]
  toggleViewSource: [i18n("toggle_view_source")]

  copyCurrentUrl: [i18n("copy_current_url")]
  'LinkHints.activateModeToCopyLinkUrl': [i18n("link_hints_activate_mode_to_copy_link_url")]
  openCopiedUrlInCurrentTab: [i18n("open_copied_url_in_current_tab"), { background: true }]
  openCopiedUrlInNewTab: [i18n("open_copied_url_in_new_tab"), { background: true }]

  enterInsertMode: [i18n("enter_insert_mode")]

  focusInput: [i18n("focus_input"), { passCountToFunction: true }]

  'LinkHints.activateMode': [i18n("link_hints_activate_mode")]
  'LinkHints.activateModeToOpenInNewTab': [i18n("link_hints_activate_mode_to_open_in_new_tab")]
  'LinkHints.activateModeWithQueue': [i18n("link_hints_activate_mode_with_queue")]

  "LinkHints.activateModeToOpenIncognito": [i18n("link_hints_activate_mode_to_open_incognito")]

  enterFindMode: [i18n("enter_find_mode")]
  performFind: [i18n("perform_find")]
  performBackwardsFind: [i18n("perform_backwards_find")]

  goPrevious: [i18n("go_previous")]
  goNext: [i18n("go_next")]

  # Navigating your history
  goBack: [i18n("go_back"), { passCountToFunction: true }]
  goForward: [i18n("go_forward"), { passCountToFunction: true }]

  # Navigating the URL hierarchy
  goUp: [i18n("go_up"), { passCountToFunction: true }]
  goToRoot: [i18n("go_to_root"), { passCountToFunction: true }]

  # Manipulating tabs
  nextTab: [i18n("next_tab"), { background: true }]
  previousTab: [i18n("previous_tab"), { background: true }]
  firstTab: [i18n("first_tab"), { background: true }]
  lastTab: [i18n("last_tab"), { background: true }]
  createTab: [i18n("create_tab"), { background: true }]
  duplicateTab: [i18n("duplicate_tab"), { background: true }]
  removeTab: [i18n("remove_tab"), { background: true, noRepeat: true }]
  restoreTab: [i18n("restore_tab"), { background: true }]
  moveTabToNewWindow: [i18n("move_tab_to_new_window"), { background: true }]

  "Vomnibar.activate": [i18n("vomnibar_activate")]
  "Vomnibar.activateInNewTab": [i18n("vomnibar_activate_in_new_tab")]
  "Vomnibar.activateTabSelection": [i18n("vomnibar_activate_tab_selection")]
  "Vomnibar.activateBookmarks": [i18n("vomnibar_activate_bookmarks")]
  "Vomnibar.activateBookmarksInNewTab": [i18n("vomnibar_activate_bookmarks_in_new_tab")]

  nextFrame: [i18n("next_frame"), { background: true, passCountToFunction: true }]

  "Marks.activateCreateMode": [i18n("marks_activate_create_mode")]
  "Marks.activateGotoMode": [i18n("marks_activate_goto_mode")]

Commands.init()

root = exports ? window
root.Commands = Commands

Commands =
  init: ->
    for mode, commandDescriptions of commandDescriptionsForMode
      for command, description of commandDescriptions
        @addCommand(command, mode, description[0], description[1])

  availableCommandsForMode: {}
  keyToCommandRegistries: {} # A mapping of mode => key => command.

  # Registers a command, making it available to be optionally bound to a key.
  # options:
  #  - background: whether this command needs to be run against the background page.
  #  - passCountToFunction: true if this command should have any digits which were typed prior to the
  #    command passed to it. This is used to implement e.g. "closing of 3 tabs".
  addCommand: (command, mode, description, options) ->
    availableCommands = @availableCommandsForMode[mode] ?= {}
    if command of availableCommands
      console.log(command, "is already defined! Check commands.coffee for duplicates.")
      return

    options ||= {}
    availableCommands[command] =
      description: description
      isBackgroundCommand: options.background
      passCountToFunction: options.passCountToFunction
      noRepeat: options.noRepeat
      repeatLimit: options.repeatLimit

  mapKeyToCommand: (key, mode, command, args) ->
    availableCommands = @availableCommandsForMode[mode] ?= {}
    unless availableCommands[command]
      console.log("#{command} doesn't exist for mode #{mode}!")
      return

    commandDetails = availableCommands[command]
    keyToCommandRegistry = @keyToCommandRegistries[mode] ?= {}

    keyToCommandRegistry[key] =
      args: args
      command: command
      isBackgroundCommand: commandDetails.isBackgroundCommand
      passCountToFunction: commandDetails.passCountToFunction
      noRepeat: commandDetails.noRepeat
      repeatLimit: commandDetails.repeatLimit

  unmapKey: (key, mode) -> delete @keyToCommandRegistries[mode][key]

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

  parseCustomKeyMappings: do ->
    lineCommandToCommandAndModes =
      map: ["map", ["normal", "visual"]]
      nmap: ["map", ["normal"]]
      vmap: ["map", ["visual"]]
      unmap: ["unmap", ["normal", "visual"]]
      nunmap: ["unmap", ["normal"]]
      vunmap: ["unmap", ["visual"]]
      unmapAll: ["unmapAll", ["normal", "visual"]]
      nunmapAll: ["unmapAll", ["normal"]]
      vunmapAll: ["unmapAll", ["visual"]]
    (customKeyMappings) ->
      lines = customKeyMappings.split("\n")

      for line in lines
        continue if (line[0] == "\"" || line[0] == "#")
        splitLine = line.split(/\s+/)

        lineCommand = splitLine[0]
        [parseCommand, modes] = lineCommandToCommandAndModes[lineCommand] ? ["", []]

        if (parseCommand == "map")
          continue if (splitLine.length < 3)
          [key, vimiumCommand, args...] = splitLine[1...]
          key = @normalizeKey(key)

          for mode in modes
            continue unless @availableCommandsForMode[mode][vimiumCommand]
            console.log("Mapping #{key} to #{vimiumCommand} in #{mode} mode")
            @mapKeyToCommand(key, mode, vimiumCommand, args)
        else if (parseCommand == "unmap")
          continue if (splitLine.length != 2)

          key = @normalizeKey(splitLine[1])
          console.log("Unapping #{key} in #{modes.join(", ")} modes")
          @unmapKey(key, mode) for mode in modes
        else if (parseCommand == "unmapAll")
          console.log("Unapping all keys in #{modes.join(", ")} modes")
          @keyToCommandRegistries[mode] = {} for mode in modes

  clearKeyMappingsAndSetDefaults: ->
    @keyToCommandRegistries = {}

    for mode, defaultKeyMappings of defaultKeyMappingsForModes
      for key, command of defaultKeyMappings
        [commandName, args...] = command.split(/\s+/)
        @mapKeyToCommand(key, mode, commandName, args)

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
      "focusInput",
      "LinkHints.activateMode",
      "LinkHints.activateModeToOpenInNewTab",
      "LinkHints.activateModeToOpenInNewForegroundTab",
      "LinkHints.activateModeWithQueue",
      "LinkHints.activateModeToDownloadLink",
      "LinkHints.activateModeToOpenIncognito",
      "Vomnibar.activate",
      "Vomnibar.activateInNewTab",
      "Vomnibar.activateTabSelection",
      "Vomnibar.activateBookmarks",
      "Vomnibar.activateBookmarksInNewTab",
      "goPrevious",
      "goNext",
      "nextFrame",
      "Marks.activateCreateMode",
      "Vomnibar.activateEditUrl",
      "Vomnibar.activateEditUrlInNewTab",
      "Marks.activateGotoMode"]
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
    visualMode: [
      "enterVisualMode",
      "exitVisualMode"
      "VisualMode.extendFront",
      "VisualMode.extendBack",
      "VisualMode.extendFocus",
      "VisualMode.extendAnchor",
      "VisualMode.yank"]

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

defaultKeyMappingsForModes =
  "normal":
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

    "H": "goBack"
    "L": "goForward"
    "gu": "goUp"
    "gU": "goToRoot"

    "gi": "focusInput"

    "f":     "LinkHints.activateMode"
    "F":     "LinkHints.activateModeToOpenInNewTab"
    "<a-f>": "LinkHints.activateModeWithQueue"

    "af": "LinkHints.activateModeToDownloadLink"

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

    "m": "Marks.activateCreateMode"
    "`": "Marks.activateGotoMode"

  visual:
    "<ESC>": "exitVisualMode"
    "h": "VisualMode.extendFocus backward"
    "l": "VisualMode.extendFocus forward"
    "k": "VisualMode.extendFocus backward line"
    "j": "VisualMode.extendFocus forward line"
    "e": "VisualMode.extendFocus backward word"
    "w": "VisualMode.extendFocus forward word"
    "0": "VisualMode.extendFocus backward lineboundary"
    "$": "VisualMode.extendFocus forward lineboundary"
    "y": "VisualMode.yank"


# This is a mapping of: commandIdentifier => [description, options].
# If the noRepeat and repeatLimit options are both specified, then noRepeat takes precedence.
commandDescriptionsForMode =
  normal:
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

    focusInput: ["Focus the first text box on the page. Cycle between them using tab",
      { passCountToFunction: true }]

    "LinkHints.activateMode": ["Open a link in the current tab", { noRepeat: true }]
    "LinkHints.activateModeToOpenInNewTab": ["Open a link in a new tab", { noRepeat: true }]
    "LinkHints.activateModeToOpenInNewForegroundTab": ["Open a link in a new tab & switch to it", { noRepeat: true }]
    "LinkHints.activateModeWithQueue": ["Open multiple links in a new tab", { noRepeat: true }]
    "LinkHints.activateModeToOpenIncognito": ["Open a link in incognito window", { noRepeat: true }]
    "LinkHints.activateModeToDownloadLink": ["Download link url", { noRepeat: true }]

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
    nextTab: ["Go one tab right", { background: true }]
    previousTab: ["Go one tab left", { background: true }]
    firstTab: ["Go to the first tab", { background: true }]
    lastTab: ["Go to the last tab", { background: true }]

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

    "Marks.activateCreateMode": ["Create a new mark", { noRepeat: true }]
    "Marks.activateGotoMode": ["Go to a mark", { noRepeat: true }]

  visual:
    "VisualMode.extendFront": ["Extend the current selection from the front"]
    "VisualMode.extendBack": ["Extend the current selection from the back"]
    "VisualMode.extendFocus": ["Extend the current selection from its endpoint"]
    "VisualMode.extendAnchor": ["Extend the current selection from its startpoint"]
    "VisualMode.yank": ["Copy the currently selected text to the clipboard"]
    exitVisualMode: ["Exit visual mode", { noRepeat: true }]

Commands.init()

root = exports ? window
root.Commands = Commands

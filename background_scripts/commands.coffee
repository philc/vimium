Commands =
  init: ->
    for groupName, commandList of commandLists
      @addCommand(command) for command in commandList

  availableCommands: {}
  keyToCommandRegistry: {}

  # Registers a command, making it available to be optionally bound to a key.
  addCommand: (command) ->
    if command.name of @availableCommands
      console.log("#{command.name} is already defined! Check commands.coffee for duplicates.")
      return

    @availableCommands[command.name] = command

  mapKeyToCommand: (key, commandName) ->
    unless commandName of @availableCommands
      console.log("#{commandName} doesn't exist!")
      return

    @keyToCommandRegistry[key] = @availableCommands[commandName]

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

      switch (lineCommand)
        when "map"
          continue if (splitLine.length != 3)
          key = @normalizeKey(splitLine[1])
          vimiumCommand = splitLine[2]

          continue unless @availableCommands[vimiumCommand]

          console.log("Mapping #{key} to #{vimiumCommand}")
          @mapKeyToCommand(key, vimiumCommand)
        when "unmap"
          continue if (splitLine.length != 2)

          key = @normalizeKey(splitLine[1])
          console.log("Unmapping #{key}")
          @unmapKey(key)
        when "unmapAll"
          @keyToCommandRegistry = {}

  clearKeyMappingsAndSetDefaults: ->
    @keyToCommandRegistry = {}

    for key of defaultKeyMappings
      @mapKeyToCommand(key, defaultKeyMappings[key])

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


Commands.init()

root = exports ? window
root.Commands = Commands

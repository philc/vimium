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
  "<ctrl-e>": "scrollDown"
  "<ctrl-y>": "scrollUp"

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
  "<alt-f>": "LinkHints.activateModeWithQueue"

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
  showHelp: ["显示帮助", { background: true }]
  scrollDown: ["向下"]
  scrollUp: ["向上"]
  scrollLeft: ["向左"]
  scrollRight: ["向右"]
  scrollToTop: ["跳到页面顶端"]
  scrollToBottom: ["跳到页面底部"]
  scrollToLeft: ["跳到页面最左边"]

  scrollToRight: ["跳到页面最右边"]
  scrollPageDown: ["往下滚屏"]
  scrollPageUp: ["往上滚屏"]
  scrollFullPageDown: ["往下翻页"]
  scrollFullPageUp: ["往上翻页"]

  reload: ["刷新页面"]
  toggleViewSource: ["查看源代码"]

  copyCurrentUrl: ["复制当前网址到剪贴板"]
  'LinkHints.activateModeToCopyLinkUrl': ["复制当前链接到剪贴板"]
  openCopiedUrlInCurrentTab: ["在当前标签打开剪贴板中的链接", { background: true }]
  openCopiedUrlInNewTab: ["在新标签中打开剪贴板中的链接", { background: true }]

  enterInsertMode: ["进入打字模式"]

  focusInput: ["指向页面中的第n个文本框", { passCountToFunction: true }]

  'LinkHints.activateMode': ["在当前标签打开指定链接"]
  'LinkHints.activateModeToOpenInNewTab': ["在新标签中打开指定链接"]
  'LinkHints.activateModeWithQueue': ["在新标签中打开指定的多个链接"]

  enterFindMode: ["进入查找模式"]
  performFind: ["向前查找下一项"]
  performBackwardsFind: ["向前查找下一项"]

  goPrevious: ["上一页"]
  goNext: ["下一页"]

  # Navigating your history
  goBack: ["后退", { passCountToFunction: true }]
  goForward: ["前进", { passCountToFunction: true }]

  # Navigating the URL hierarchy
  goUp: ["打开父目录", { passCountToFunction: true }]

  # Manipulating tabs
  nextTab: ["打开到右标签", { background: true }]
  previousTab: ["打开左标签", { background: true }]
  firstTab: ["打开第一个标签", { background: true }]
  lastTab: ["打开最后一个标签", { background: true }]
  createTab: ["打开新标签", { background: true }]
  removeTab: ["关闭当前标签", { background: true }]
  restoreTab: ["重新打开关闭的标签", { background: true }]

  "Vomnibar.activate": ["在当前标签打开..."]
  "Vomnibar.activateInNewTab": ["在新标签中打开..."]
  "Vomnibar.activateTabSelection": ["搜索打开的标签..."]
  "Vomnibar.activateBookmarks": ["在当前标签打开收藏夹..."]
  "Vomnibar.activateBookmarksInNewTab": ["在新标签中打开收藏夹..."]

  nextFrame: ["跳转到下一个框架页", { background: true, passCountToFunction: true }]

  "Marks.activateCreateMode": ["在当前位置设定一个标记"]
  "Marks.activateGotoMode": ["跳转到指定标记"]

Commands.init()

root = exports ? window
root.Commands = Commands

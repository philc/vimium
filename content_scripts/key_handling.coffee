KeyHandler =
  keyQueue: "" # Queue of keys typed
  validFirstKeys: {}
  keyToCommandRegistry: {}

  # Keys are either literal characters, or "named" - for example <a-b> (alt+b), <left> (left arrow) or <f12>.
  # This regular expression captures two groups: the first is a named key, the second is the remainder of the
  # string.
  namedKeyRegex: /^(<(?:[amc]-.|(?:[amc]-)?[a-z0-9]{2,5})>)(.*)$/

  # Used to log our key handling progress to the background page.
  log: (data) ->
    chrome.runtime.sendMessage
      handler: "log"
      data: data
      frameId: frameId

  # Returns true if the most recent key was handled, false otherwise.
  # No command is executed if the second argument is true, so that we can handle keydowns for keys that
  # should be activated by a keypress listener.
  handleKeyDown: (key, noAction) ->
    keyHandled = false
    if (key == "<ESC>")
      @log("clearing keyQueue")
      @keyQueue = ""
    else
      @log("checking keyQueue: [#{@keyQueue + key}]") unless noAction
      keyHandled = @checkKeyQueue(@keyQueue + key, noAction)
      @log("new KeyQueue: " + @keyQueue) unless noAction

    keyHandled

  splitKeyIntoFirstAndSecond: (key) ->
    if (key.search(@namedKeyRegex) == 0)
      { first: RegExp.$1, second: RegExp.$2 }
    else
      { first: key[0], second: key.slice(1) }

  refreshKeyToCommandRegistry: (request) ->
    @keyToCommandRegistry = request.keyToCommandRegistry
    @populateValidFirstKeys()

  populateValidFirstKeys: ->
    for key of @keyToCommandRegistry
      @validFirstKeys[@splitKeyIntoFirstAndSecond(key).first] = true

  splitKeyQueue: (queue) ->
    match = /([1-9][0-9]*)?(.*)/.exec(queue)
    count = parseInt(match[1], 10)
    command = match[2]

    { count: count, command: command }

  # Returns true if the most recent key was handled, false otherwise.
  # No command is executed if the second argument is true, so that we can handle keydowns for keys that
  # should be activated by a keypress listener.
  checkKeyQueue: (keysToCheck, noAction) ->
    keyHandled = true
    splitHash = @splitKeyQueue(keysToCheck)
    command = splitHash.command
    count = splitHash.count

    if command.length == 0
      @keyQueue = keysToCheck unless noAction
      return true
    count = 1 if isNaN(count)

    if (@keyToCommandRegistry[command])
      return true if noAction
      registryEntry = @keyToCommandRegistry[command]
      runCommand = true

      if registryEntry.noRepeat
        count = 1
      else if registryEntry.repeatLimit and count > registryEntry.repeatLimit
        runCommand = confirm """
          You have asked Vimium to perform #{count} repeats of the command:
          #{registryEntry.description}

          Are you sure you want to continue?
        """

      if runCommand
        if not registryEntry.isBackgroundCommand
          if (registryEntry.passCountToFunction)
            Utils.invokeCommandString(registryEntry.command, [count])
          else
            Utils.invokeCommandString(registryEntry.command) for i in [0...count]
        else
          chrome.runtime.sendMessage
            handler: "executeBackgroundCommand",
            command: registryEntry.command,
            frameId: frameId,
            count: count,
            passCountToFunction: registryEntry.passCountToFunction,
            noRepeat: registryEntry.noRepeat

      newKeyQueue = ""
    else if ((splitKey = @splitKeyIntoFirstAndSecond(command)).second != "")
      # The second key might be a valid command by its self.
      if (@keyToCommandRegistry[splitKey.second])
        keyHandled = @checkKeyQueue(splitKey.second, noAction)
        newKeyQueue = @keyQueue
      else
        if @validFirstKeys[splitKey.second]
          newKeyQueue = splitKey.second
          keyHandled = true
        else
          newKeyQueue = ""
          keyHandled = false
    else
      if @validFirstKeys[command]
        newKeyQueue = count.toString() + command
        keyHandled = true
      else
        newKeyQueue = ""
        keyHandled = false

    @keyQueue = newKeyQueue unless noAction
    keyHandled

root = exports ? window
root.KeyHandler = KeyHandler

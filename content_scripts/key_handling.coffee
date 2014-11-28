KeyHandler =
  keyQueue: "" # Queue of keys typed
  completionKeys: []
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

  handleKeyDown: (request) ->
    key = request.keyChar
    if (key == "<ESC>")
      @log("clearing keyQueue")
      @keyQueue = ""
    else
      @log("checking keyQueue: [#{@keyQueue + key}]")
      @keyQueue = @checkKeyQueue(@keyQueue + key, request.frameId)
      @log("new KeyQueue: " + @keyQueue)

  splitKeyIntoFirstAndSecond: (key) ->
    if (key.search(@namedKeyRegex) == 0)
      { first: RegExp.$1, second: RegExp.$2 }
    else
      { first: key[0], second: key.slice(1) }

  getActualKeyStrokeLength: (key) ->
    if (key.search(@namedKeyRegex) == 0)
      1 + @getActualKeyStrokeLength(RegExp.$2)
    else
      key.length

  refreshKeyToCommandRegistry: (request) ->
    @keyToCommandRegistry = request.keyToCommandRegistry
    @populateValidFirstKeys()

    @generateCompletionKeys("")

  populateValidFirstKeys: ->
    for key of @keyToCommandRegistry
      @validFirstKeys[@splitKeyIntoFirstAndSecond(key).first] = true

  splitKeyQueue: (queue) ->
    match = /([1-9][0-9]*)?(.*)/.exec(queue)
    count = parseInt(match[1], 10)
    command = match[2]

    { count: count, command: command }

  checkKeyQueue: (keysToCheck, frameId) ->
    splitHash = @splitKeyQueue(keysToCheck)
    command = splitHash.command
    count = splitHash.count

    return keysToCheck if command.length == 0
    count = 1 if isNaN(count)

    if (@keyToCommandRegistry[command])
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
    else if (@getActualKeyStrokeLength(command) > 1)
      splitKey = @splitKeyIntoFirstAndSecond(command)

      # The second key might be a valid command by its self.
      if (@keyToCommandRegistry[splitKey.second])
        newKeyQueue = @checkKeyQueue(splitKey.second, frameId)
      else
        newKeyQueue = (if @validFirstKeys[splitKey.second] then splitKey.second else "")
    else
      newKeyQueue = (if @validFirstKeys[command] then count.toString() + command else "")

    # Send the completion keys to vimium_frontend.coffee.
    @generateCompletionKeys(newKeyQueue)

    newKeyQueue

  # Generates a list of keys that can complete a valid command given the current key queue or the one passed in
  generateCompletionKeys: (keysToCheck) ->
    splitHash = @splitKeyQueue(keysToCheck || @keyQueue)
    command = splitHash.command
    count = splitHash.count

    @completionKeys = []

    if (@getActualKeyStrokeLength(command) == 1)
      for key of @keyToCommandRegistry
        splitKey = @splitKeyIntoFirstAndSecond(key)
        if (splitKey.first == command)
          @completionKeys.push(splitKey.second)

    @completionKeys

root = exports ? window
root.KeyHandler = KeyHandler

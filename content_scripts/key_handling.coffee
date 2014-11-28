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
    keyHandled = false
    if (key == "<ESC>")
      @log("clearing keyQueue")
      @keyQueue = ""
    else
      @log("checking keyQueue: [#{@keyQueue + key}]")
      keyHandled = @checkKeyQueue(@keyQueue + key, request.frameId)
      @log("new KeyQueue: " + @keyQueue)

    keyHandled

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

  # Returns true if the most recent key was handled, false otherwise.
  checkKeyQueue: (keysToCheck, frameId) ->
    keyHandled = true
    splitHash = @splitKeyQueue(keysToCheck)
    command = splitHash.command
    count = splitHash.count

    if command.length == 0
      @keyQueue = keysToCheck
      return true
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

      @keyQueue = ""
    else if (@getActualKeyStrokeLength(command) > 1)
      splitKey = @splitKeyIntoFirstAndSecond(command)

      # The second key might be a valid command by its self.
      if (@keyToCommandRegistry[splitKey.second])
        keyHandled = @checkKeyQueue(splitKey.second, frameId)
      else
        if @validFirstKeys[splitKey.second]
          @keyQueue = splitKey.second
          keyHandled = true
        else
          @keyQueue = ""
          keyHandled = false
    else
      if @validFirstKeys[command]
        @keyQueue = count.toString() + command
        keyHandled = true
      else
        @keyQueue = ""
        keyHandled = false

    # Send the completion keys to vimium_frontend.coffee.
    @generateCompletionKeys(@keyQueue)

    keyHandled

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

  willHandleKey: (keyChar) ->
    @completionKeys.indexOf(keyChar) != -1 or @validFirstKeys[keyChar] or /^[1-9]/.test(keyChar)

root = exports ? window
root.KeyHandler = KeyHandler

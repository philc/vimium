KeyHandler =
  keyQueue: "" # Queue of keys typed
  validFirstKeys: {}
  singleKeyCommands: []
  keyToCommandRegistry: {}

  # Keys are either literal characters, or "named" - for example <a-b> (alt+b), <left> (left arrow) or <f12>.
  # This regular expression captures two groups: the first is a named key, the second is the remainder of the
  # string.
  namedKeyRegex: /^(<(?:[amc]-.|(?:[amc]-)?[a-z0-9]{2,5})>)(.*)$/

  handleKeyDown: (request) ->
    key = request.keyChar
    if (key == "<ESC>")
      console.log("clearing keyQueue")
      @keyQueue = ""
    else
      console.log("checking keyQueue: [", @keyQueue + key, "]")
      @keyQueue = @checkKeyQueue(@keyQueue + key, request.frameId)
      console.log("new KeyQueue: " + @keyQueue)
    # Tell the content script whether there are keys in the queue.
    # FIXME: There is a race condition here.  The behaviour in the content script depends upon whether this
    # message gets back there before or after the next keystroke.
    # That being said, I suspect there are other similar race conditions here, for example in
    # checkKeyQueue().  Steve (23 Aug, 14).
    requestHandlers.currentKeyQueue
      name: "currentKeyQueue",
      keyQueue: @keyQueue

  #
  # Returns the keys that can complete a valid command given the current key queue.
  #
  getCompletionKeysRequest: (keysToCheck = "") ->
    name: "refreshCompletionKeys"
    completionKeys: @generateCompletionKeys(keysToCheck)
    validFirstKeys: @validFirstKeys

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
    @populateSingleKeyCommands()

    requestHandlers.refreshCompletionKeys(@getCompletionKeysRequest())

  populateValidFirstKeys: ->
    for key of @keyToCommandRegistry
      if (@getActualKeyStrokeLength(key) == 2)
        @validFirstKeys[@splitKeyIntoFirstAndSecond(key).first] = true

  populateSingleKeyCommands: ->
    for key of @keyToCommandRegistry
      if (@getActualKeyStrokeLength(key) == 1)
        @singleKeyCommands.push(key)

  splitKeyQueue: (queue) ->
    match = /([1-9][0-9]*)?(.*)/.exec(queue)
    count = parseInt(match[1], 10)
    command = match[2]

    { count: count, command: command }

  checkKeyQueue: (keysToCheck, frameId) ->
    refreshedCompletionKeys = false
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
          requestHandlers.executePageCommand(
            name: "executePageCommand",
            command: registryEntry.command,
            frameId: frameId,
            count: count,
            passCountToFunction: registryEntry.passCountToFunction,
            completionKeys: @generateCompletionKeys(""))
          refreshedCompletionKeys = true
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

    # If we haven't sent the completion keys piggybacked on executePageCommand,
    # send them by themselves.
    unless refreshedCompletionKeys
      requestHandlers.refreshCompletionKeys(@getCompletionKeysRequest(newKeyQueue))

    newKeyQueue

  # Generates a list of keys that can complete a valid command given the current key queue or the one passed in
  generateCompletionKeys: (keysToCheck) ->
    splitHash = @splitKeyQueue(keysToCheck || @keyQueue)
    command = splitHash.command
    count = splitHash.count

    completionKeys = @singleKeyCommands.slice(0)

    if (@getActualKeyStrokeLength(command) == 1)
      for key of @keyToCommandRegistry
        splitKey = @splitKeyIntoFirstAndSecond(key)
        if (splitKey.first == command)
          completionKeys.push(splitKey.second)

    completionKeys

root = exports ? window
root.KeyHandler = KeyHandler

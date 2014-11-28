KeyHandler =
  keyQueue: [] # Queue of keys typed
  keyToCommandRegistry: {}

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
      @keyQueue = []
    else
      newKeyQueue = @keyQueue.concat([key])
      @log("checking keyQueue: [#{newKeyQueue.join("")}]") unless noAction
      keyHandled = @checkKeyQueue(newKeyQueue, noAction)
      @log("new KeyQueue: " + @keyQueue) unless noAction

    keyHandled

  refreshKeyToCommandRegistry: (request) -> @keyToCommandRegistry = request.keyToCommandRegistry

  splitKeyQueue: (queue) ->
    l = queue.length
    if l > 0 and queue[0].match /^[1-9]$/
      i = 1
      while i < l and queue[i].match /^[0-9]$/
        i++
      count = parseInt(queue[0..i-1].join(""), 10)
      {count: count, command: queue[i..]}
    else
      {count: 1, command: queue}

  isPartialCommand: (command) ->
    for key of @keyToCommandRegistry
      return true if key.indexOf(command) == 0
    false

  # Returns true if the most recent key was handled, false otherwise.
  # No command is executed if the second argument is true, so that we can handle keydowns for keys that
  # should be activated by a keypress listener.
  checkKeyQueue: (keysToCheck, noAction) ->
    keyHandled = true
    splitHash = @splitKeyQueue(keysToCheck)
    count = splitHash.count
    commandQueue = splitHash.command
    command = commandQueue.join("")

    if commandQueue.length == 0
      @keyQueue = keysToCheck unless noAction
      return true

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

      newKeyQueue = []
      keyHandled = true
    else if @isPartialCommand command
      newKeyQueue = keysToCheck
      keyHandled = true
    else if commandQueue.length > 1
      commandQueue.shift()
      keyHandled = @checkKeyQueue(commandQueue, noAction)
      newKeyQueue = @keyQueue
    else
      newKeyQueue = []
      keyHandled = false

    @keyQueue = newKeyQueue unless noAction
    keyHandled

root = exports ? window
root.KeyHandler = KeyHandler

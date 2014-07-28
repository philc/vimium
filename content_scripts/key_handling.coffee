window.addEventListener "message", (event) ->
  return unless event.data?.name == "vimiumKeyDown" # This message isn't intended for us

  return unless event.ports.length == 1
  windowPort = event.ports[0]

  windowPort.onmessage = (event) ->
    handleKeyDown event.data, windowPort

, false


keyQueue = "" # Queue of keys typed
validFirstKeys = {}
singleKeyCommands = []

# Keys are either literal characters, or "named" - for example <a-b> (alt+b), <left> (left arrow) or <f12>
# This regular expression captures two groups: the first is a named key, the second is the remainder of
# the string.
namedKeyRegex = /^(<(?:[amc]-.|(?:[amc]-)?[a-z0-9]{2,5})>)(.*)$/

splitKeyIntoFirstAndSecond = (key) ->
  if (key.search(namedKeyRegex) == 0)
    { first: RegExp.$1, second: RegExp.$2 }
  else
    { first: key[0], second: key.slice(1) }

getActualKeyStrokeLength = (key) ->
  if (key.search(namedKeyRegex) == 0)
    1 + getActualKeyStrokeLength(RegExp.$2)
  else
    key.length

populateValidFirstKeys = ->
  for key of Commands.keyToCommandRegistry
    if (getActualKeyStrokeLength(key) == 2)
      validFirstKeys[splitKeyIntoFirstAndSecond(key).first] = true

populateSingleKeyCommands = ->
  for key of Commands.keyToCommandRegistry
    if (getActualKeyStrokeLength(key) == 1)
      singleKeyCommands.push(key)

splitKeyQueue = (queue) ->
  match = /([1-9][0-9]*)?(.*)/.exec(queue)
  count = parseInt(match[1], 10)
  command = match[2]

  { count: count, command: command }

handleKeyDown = (request, port) ->
  key = request.keyChar
  if key == "" # Request for completion keys
    port.postMessage getCompletionKeysRequest()
  else if key == "<ESC>"
    console.log("clearing keyQueue")
    keyQueue = ""
  else
    console.log("checking keyQueue: [", keyQueue + key, "]")
    keyQueue = checkKeyQueue(keyQueue + key, port)
    console.log("new KeyQueue: " + keyQueue)

checkKeyQueue = (keysToCheck, port) ->
  refreshedCompletionKeys = false
  splitHash = splitKeyQueue(keysToCheck)
  command = splitHash.command
  count = splitHash.count

  return keysToCheck if command.length == 0
  count = 1 if isNaN(count)

  if (Commands.keyToCommandRegistry[command])
    registryEntry = Commands.keyToCommandRegistry[command]

    if registryEntry.isBackgroundCommand
      messageObject =
        handler: "executeBackgroundCommand"
        command: registryEntry.command
        count: count
        passCountToFunction: registryEntry.passCountToFunction == true
        noRepeat: registryEntry.noRepeat == true
        completionKeys: generateCompletionKeys("")
      chrome.runtime.sendMessage(messageObject)
    else
      port.postMessage
        command: registryEntry.command
        count: count
        passCountToFunction: registryEntry.passCountToFunction == true
        noRepeat: registryEntry.noRepeat == true
        completionKeys: generateCompletionKeys("")
      refreshedCompletionKeys = true

    newKeyQueue = ""
  else if (getActualKeyStrokeLength(command) > 1)
    splitKey = splitKeyIntoFirstAndSecond(command)

    # The second key might be a valid command by its self.
    if (Commands.keyToCommandRegistry[splitKey.second])
      newKeyQueue = checkKeyQueue splitKey.second, port
    else
      newKeyQueue = (if validFirstKeys[splitKey.second] then splitKey.second else "")
  else
    newKeyQueue = (if validFirstKeys[command] then count.toString() + command else "")

  # If we haven't sent the completion keys piggybacked on executePageCommand,
  # send them by themselves.
  unless refreshedCompletionKeys
    port.postMessage getCompletionKeysRequest(null, newKeyQueue)

  newKeyQueue

# Generates a list of keys that can complete a valid command given the current key queue or the one passed in
generateCompletionKeys = (keysToCheck) ->
  splitHash = splitKeyQueue(keysToCheck || keyQueue)
  command = splitHash.command
  count = splitHash.count

  completionKeys = singleKeyCommands.slice(0)

  if (getActualKeyStrokeLength(command) == 1)
    for key of Commands.keyToCommandRegistry
      splitKey = splitKeyIntoFirstAndSecond(key)
      if (splitKey.first == command)
        completionKeys.push(splitKey.second)

  completionKeys

#
# Returns the keys that can complete a valid command given the current key queue.
#
getCompletionKeysRequest = (request, keysToCheck = "") ->
  completionKeys: generateCompletionKeys(keysToCheck)
  validFirstKeys: validFirstKeys

#
# Begin initialization.
#
settings.addEventListener "load", ->
  Commands.clearKeyMappingsAndSetDefaults()

  Commands.parseCustomKeyMappings(settings.get("keyMappings"))

  populateValidFirstKeys()
  populateSingleKeyCommands()

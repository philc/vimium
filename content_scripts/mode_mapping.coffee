class MappingMode extends Mode
  constructor: (options) ->
    super options

    # Queue of keys typed. If keyQueue.numericPrefix is true, its 0th entry is the current command's numeric
    # prefix.
    @keyQueue = []
    @push
      _name: "mode-#{@id}/registerKeyQueue"
      registerKeyQueue: ({keyQueue}) => @alwaysContinueBubbling => @keyQueue = keyQueue

  isCommandKey: (key) ->
    matched = false
    checkKeyQueue @keyQueue.concat([key]), @getCommandKeys(), (-> matched = true), (-> matched = true)
    matched

  clearKeyQueue: ->
    bgLog "clearing keyQueue"
    @keyQueue = []

  pushKeyToKeyQueue: (key) ->
    @keyQueue.push key
    bgLog "checking keyQueue: [", @keyQueue.join(""), "]"
    matched = false

    @keyQueue = checkKeyQueue @keyQueue, @getCommandKeys(), ((command, count) =>
      @matchedKeyHandler command, count
      matched = true
    ), (-> matched = true)

    handlerStack.bubbleEvent "registerKeyQueue", {keyQueue: @keyQueue}
    bgLog "new KeyQueue: " + @keyQueue.join("")
    matched

# Returns true if the keys in keys1 match the first keys in keys2.
keysPartialMatch = (keys1, keys2) ->
  return false if keys1.length > keys2.length
  for key, i in keys1
    return false if key != keys2[i]
  true

simplifyNumericPrefix = (keys) ->
  keys = keys[0..] # Make a copy of keys so the passed array isn't mutated.
  keys.numericPrefix = /^[1-9]/.test (keys[0] or "")

  if keys.numericPrefix
    i = 1
    i++ while i < keys.length and /^[0-9]/.test keys[i]
    # keysToCheck[1..i] are numeric, remove them from the array and append them to the prefix.
    keys[0] += keys.splice(1, i - 1).join ""

  keys

checkKeyQueue = (keysToCheck, commandKeys, successCallback, partialMatchCallback) ->
  keys = simplifyNumericPrefix keysToCheck

  if keys.numericPrefix
    [count, command...] = keys
    count = (parseInt count, 10) or 1
  else
    command = keys
    count = 1

  if command.length == 0
    partialMatchCallback? "", count if keys.numericPrefix
    return keysToCheck

  partiallyMatchingCommands = commandKeys.filter keysPartialMatch.bind null, command

  if partiallyMatchingCommands.length > 0
    [finalCommand] = partiallyMatchingCommands.filter ({length}) -> command.length == length
    if finalCommand
      successCallback? command.join(""), count
      newKeyQueue = []
    else
      newKeyQueue = keys
      partialMatchCallback? command.join(""), count
  else
    newKeyQueue = checkKeyQueue command[1..], commandKeys, successCallback, partialMatchCallback

  newKeyQueue

root = exports ? window
root.MappingMode = MappingMode

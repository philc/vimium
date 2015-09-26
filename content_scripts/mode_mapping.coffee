#
# Implements key handling for modes with mappings.
#
# This class attempts to match typed keys against mappings, accepting an optional numeric prefix of the form
# /[1-9][0-9]*/. It suppresses matched keys and calls @matchedKeyHandler with a complete mapping when one has
# been entered.
#
# Modes inheriting from this need to supply:
#
# getCommandKeys:
#   A function which accepts no arguments.
#   The return value should be an array of accepted mappings, where each mapping is an array of strings, one
#   string per key.
#
# matchedKeyHandler:
#   A function which accepts arguments command and count.
#   command:
#     A string representing a mapping (equivalent to .join("") -ing one of the mappings from getCommandKeys).
#   count:
#     the number of numeric prefix of the command, representing how many times the command should be
#     repeated.
#   This function is run when the user enters a complete mapping, optionally including a numeric prefix.
#
# A mode inheriting from this *cannot* use keydown/keypress/keyup in the options argument to register
# corresponding event listeners; these will be overwritten by the listeners for this mode. Any other option
# supported by Mode can be passed and will be instantiated as on Mode.
#
class MappingMode extends Mode
  constructor: (options) ->
    extend options,
      keydown: (event) => onKeydown.call @, event
      keypress: (event) => onKeypress.call @, event
      keyup: (event) => onKeyup.call @, event

    super options

    # Queue of keys typed. If keyQueue.numericPrefix is true, its 0th entry is the current command's numeric
    # prefix.
    @keyQueue = []
    @push
      _name: "mode-#{@id}/registerKeyQueue"
      registerKeyQueue: ({keyQueue}) => @alwaysContinueBubbling => @keyQueue = keyQueue

  # Tests whether the key is part of a mapping, given the current state of the key queue.
  isCommandKey: (key) ->
    matched = false
    checkKeyQueue @keyQueue.concat([key]), @getCommandKeys(), (-> matched = true), (-> matched = true)
    matched

  clearKeyQueue: ->
    bgLog "clearing keyQueue"
    @keyQueue = []

  # Adds the key to the current key queue, and test the key queue to see if any mappings match.
  # Returns truthy for a partial or complete match. Also triggers @matchedKeyHandler for complete matches.
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

# Combine any keys that represent a numeric prefix into a single string. If such a numeric prefix exists,
# numericPrefix = true will be set on the returned array.
simplifyNumericPrefix = (keys) ->
  keys = keys[0..] # Make a copy of keys so the passed array isn't mutated.
  keys.numericPrefix = /^[1-9]/.test (keys[0] or "")

  if keys.numericPrefix
    i = 1
    i++ while i < keys.length and /^[0-9]/.test keys[i]
    # keysToCheck[1..i] are numeric, remove them from the array and append them to the prefix.
    keys[0] += keys.splice(1, i - 1).join ""

  keys

# Check whether keysToCheck represents a partial or full match for any of the mappings provided by
# commandKeys.
# If keysToCheck matches a mapping in commandKeys completely, successCallback is called with arguments
#   command:
#     A string representing the mapping that was matched.
#   count:
#     The number prefix associated with this match, representing the number of times to repeat the command.
# If keysToCheck matches a mapping in commandKeys partially, partialMatchCallback is called with arguments
#   command:
#     A string representing the typed command in its current state of completion.
#   count:
#     The number prefix.
# The return value is the new state of the key queue. For a full match, all keys have been consumed, so []
# will be returned. Otherwise, the largest suffix of keysToCheck which partially matches a mapping is
# returned instead.
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
    return keys

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

#
# Adds printing characters to the key queue, and suppresses the event if there is a match.
#
# The this/@ object is an instance of MappingMode.
onKeypress = (event) ->
  keyChar = ""

  # Ignore modifier keys by themselves.
  if (event.keyCode > 31)
    keyChar = String.fromCharCode(event.charCode)

    if (keyChar)
      if @pushKeyToKeyQueue keyChar
        DomUtils.suppressEvent(event)
        return @stopBubblingAndTrue

  return @continueBubbling

#
# Adds non-printing characters to the key queue, and suppresses the event if there is a match.
# Also suppresses events for printing character that look as though they will match.
#
# The this/@ object is an instance of MappingMode.
onKeydown = (event) ->
  keyChar = ""

  # handle special keys, and normal input keys with modifiers being pressed. don't handle shiftKey alone (to
  # avoid / being interpreted as ?
  if (((event.metaKey || event.ctrlKey || event.altKey) && event.keyCode > 31) || (
      # TODO(philc): some events don't have a keyidentifier. How is that possible?
      event.keyIdentifier && event.keyIdentifier.slice(0, 2) != "U+"))
    keyChar = KeyboardUtils.getKeyChar(event)
    # Again, ignore just modifiers. Maybe this should replace the keyCode>31 condition.
    if keyChar != ""
      keyChar = keyChar.toUpperCase() if event.shiftKey

      modifiers = ""

      modifiers += "m-" if event.metaKey
      modifiers += "c-" if event.ctrlKey
      modifiers += "a-" if event.altKey

      keyChar = modifiers + keyChar
      keyChar = "<#{keyChar}>" if keyChar.length > 1

  if (keyChar)
    if @pushKeyToKeyQueue keyChar
      DomUtils.suppressEvent event
      KeydownEvents.push event
      return @stopBubblingAndTrue

  else if (KeyboardUtils.isEscape(event))
    @clearKeyQueue()

  # Added to prevent propagating this event to other listeners if it's one that'll trigger a Vimium command.
  # The goal is to avoid the scenario where Google Instant Search uses every keydown event to dump us
  # back into the search box. As a side effect, this should also prevent overriding by other sites.
  #
  # Subject to internationalization issues since we're using keyIdentifier instead of charCode (in keypress).
  #
  # TOOD(ilya): Revisit this. Not sure it's the absolute best approach.
  if keyChar == "" && @isCommandKey KeyboardUtils.getKeyChar(event)
    DomUtils.suppressPropagation(event)
    KeydownEvents.push event
    return @stopBubblingAndTrue

  return @continueBubbling

#
# Suppresses the event if a corresponding keydown event was passed previously.
#
# The this/@ object is an instance of MappingMode.
onKeyup = (event) ->
  return @continueBubbling unless KeydownEvents.pop event
  DomUtils.suppressPropagation(event)
  @stopBubblingAndTrue

root = exports ? window
root.MappingMode = MappingMode

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

#
# Sends everything except i & ESC to the handler in background_page. i & ESC are special because they control
# insert mode which is local state to the page. The key will be are either a single ascii letter or a
# key-modifier pair, e.g. <c-a> for control a.
#
# Note that some keys will only register keydown events and not keystroke events, e.g. ESC.
#
# @/this, here, is the the normal-mode Mode object.
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

# @/this, here, is the the normal-mode Mode object.
onKeydown = (event) ->
  keyChar = ""

  # handle special keys, and normal input keys with modifiers being pressed. don't handle shiftKey alone (to
  # avoid / being interpreted as ?
  if (((event.metaKey || event.ctrlKey || event.altKey) && event.keyCode > 31) || (
      # TODO(philc): some events don't have a keyidentifier. How is that possible?
      event.keyIdentifier && event.keyIdentifier.slice(0, 2) != "U+"))
    keyChar = KeyboardUtils.getKeyChar(event)
    # Again, ignore just modifiers. Maybe this should replace the keyCode>31 condition.
    if (keyChar != "")
      modifiers = []

      if (event.shiftKey)
        keyChar = keyChar.toUpperCase()
      if (event.metaKey)
        modifiers.push("m")
      if (event.ctrlKey)
        modifiers.push("c")
      if (event.altKey)
        modifiers.push("a")

      for i of modifiers
        keyChar = modifiers[i] + "-" + keyChar

      if (modifiers.length > 0 || keyChar.length > 1)
        keyChar = "<" + keyChar + ">"

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

# @/this, here, is the the normal-mode Mode object.
onKeyup = (event) ->
  return @continueBubbling unless KeydownEvents.pop event
  DomUtils.suppressPropagation(event)
  @stopBubblingAndTrue

root = exports ? window
root.MappingMode = MappingMode

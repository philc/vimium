class NormalMode extends KeyHandlerMode
  constructor: (options = {}) ->
    defaults =
      name: "normal"
      indicator: false # There is normally no mode indicator in normal mode.
      commandHandler: @commandHandler.bind this

    super extend defaults, options

    chrome.storage.local.get "normalModeKeyStateMapping", (items) =>
      @setKeyMapping items.normalModeKeyStateMapping

    chrome.storage.onChanged.addListener (changes, area) =>
      if area == "local" and changes.normalModeKeyStateMapping?.newValue
        @setKeyMapping changes.normalModeKeyStateMapping.newValue

  commandHandler: ({command: registryEntry, count}) ->
    count *= registryEntry.options.count ? 1
    count = 1 if registryEntry.noRepeat

    if registryEntry.repeatLimit? and registryEntry.repeatLimit < count
      return unless confirm """
        You have asked Vimium to perform #{count} repetitions of the command: #{registryEntry.description}.\n
        Are you sure you want to continue?"""

    if registryEntry.topFrame
      # We never return to a UI-component frame (e.g. the help dialog), it might have lost the focus.
      sourceFrameId = if window.isVimiumUIComponent then 0 else frameId
      chrome.runtime.sendMessage
        handler: "sendMessageToFrames", message: {name: "runInTopFrame", sourceFrameId, registryEntry}
    else if registryEntry.background
      chrome.runtime.sendMessage {handler: "runBackgroundCommand", registryEntry, count}
    else
      Utils.invokeCommandString registryEntry.command, count, {registryEntry}

root = exports ? (window.root ?= {})
root.NormalMode = NormalMode
extend window, root unless exports?

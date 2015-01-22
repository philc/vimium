
# This prevents unmapped printable characters from being passed through to underlying page.
class SuppressPrintable extends Mode
  constructor: (options) ->

    handler = (event) =>
      if KeyboardUtils.isPrintable event
        if event.type == "keydown"
          DomUtils. suppressPropagation
          @stopBubblingAndTrue
        else
          @suppressEvent
      else
        @stopBubblingAndTrue

    @suppressPrintableHandlerId = handlerStack.push
      _name: "movement/suppress-printable"
      keydown: handler
      keypress: handler
      keyup: handler

    super options
    @onExit => handlerStack.remove @suppressPrintableHandlerId

# This watches keyboard events, and maintains @countPrefix as count-prefic and other keys are pressed.
class MaintainCount extends SuppressPrintable
  constructor: (options) ->
    @countPrefix = ""
    super options

    isNumberKey = (keyChar) ->
      keyChar and keyChar.length == 1 and "0" <= keyChar <= "9"

    @push
      _name: "movement/maintain-count"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            @countPrefix = if isNumberKey keyChar then @countPrefix + keyChar else ""

  countPrefixTimes: (func) ->
    countPrefix = if 0 < @countPrefix.length then parseInt @countPrefix else 1
    @countPrefix = ""
    func() for [0...countPrefix]

# This implements movement commands with count prefixes (using MaintainCount) for visual and edit modes.
class Movement extends MaintainCount
  movements:
    h: "backward character"
    l: "forward character"
    k: "backward line"
    j: "forward line"
    b: "backward word"
    e: "forward word"

  constructor: (options) ->
    @alterMethod = options.alterMethod || "extend"
    super options

    @push
      _name: "movement"
      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            keyChar = String.fromCharCode event.charCode
            if @movements[keyChar]
              @countPrefixTimes =>
                if "string" == typeof @movements[keyChar]
                  window.getSelection().modify @alterMethod, @movements[keyChar].split(/\s+/)...
                else if "function" == typeof @movements[keyChar]
                  @movements[keyChar]()

class VisualMode extends Movement
  constructor: (options = {}) ->
    defaults =
      name: "visual"
      badge: "V"
      exitOnEscape: true
      exitOnBlur: options.targetElement
      alterMethod: "extend"

      keypress: (event) =>
        @alwaysContinueBubbling =>
          unless event.metaKey or event.ctrlKey or event.altKey
            switch String.fromCharCode event.charCode
              when "y"
                chrome.runtime.sendMessage
                  handler: "copyToClipboard"
                  data: window.getSelection().toString()
                @exit()
                # TODO(smblott). Suppress next keyup.

    super extend defaults, options
    @debug = true

class EditMode extends Movement
  @activeElements = []

  constructor: (options = {}) ->
    defaults =
      name: "edit"
      exitOnEscape: true
      alterMethod: "move"
      keydown: (event) => if @isActive() then @handleKeydown event else @continueBubbling
      keypress: (event) => if @isActive() then @handleKeypress event else @continueBubbling
      keyup: (event) => if @isActive() then @handleKeyup event else @continueBubbling

    @element = document.activeElement
    if @element and DomUtils.isEditable @element
      super extend defaults, options

  handleKeydown: (event) ->
    @stopBubblingAndTrue
  handleKeypress: (event) ->
    @suppressEvent
  handleKeyup: (event) ->
    @stopBubblingAndTrue

  isActive: ->
    document.activeElement and DomUtils.isDOMDescendant @element, document.activeElement

  exit: (event, target) ->
    super()
    @element.blur() if target? and DomUtils.isDOMDescendant @element, target
    EditMode.activeElements = EditMode.activeElements.filter (element) => element != @element

  updateBadge: (badge) ->
    badge.badge = "E" if @isActive()

root = exports ? window
root.VisualMode = VisualMode
root.EditMode = EditMode

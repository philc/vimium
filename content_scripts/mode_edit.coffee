
class EditMode extends Mode
  @activeElements = []

  constructor: (options = {}) ->
    defaults =
      name: "edit"
      exitOnEscape: true
      keydown: (event) => if @isActive() then @handleKeydown event else @continueBubbling
      keypress: (event) => if @isActive() then @handleKeypress event else @continueBubbling
      keyup: (event) => if @isActive() then @handleKeyup event else @continueBubbling

    @element = document.activeElement
    if @element and DomUtils.isEditable @element
      super extend defaults, options

  handleKeydown: (event) -> @suppressEvent
  handleKeypress: (event) -> @suppressEvent
  handleKeyup: (event) -> @suppressEvent

  isActive: ->
    document.activeElement and DomUtils.isDOMDescendant @element, document.activeElement

  exit: (event, target) ->
    super()
    @element.blur() if target? and DomUtils.isDOMDescendant @element, target
    EditMode.activeElements = EditMode.activeElements.filter (element) => element != @element

  updateBadge: (badge) ->
    badge.badge = "E" if @isActive()

root = exports ? window
root.EditMode = EditMode

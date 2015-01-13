
class InsertMode extends Mode
  constructor: (options = {}) ->
    defaults =
      name: "insert"
      exitOnEscape: true
      keydown: (event) => @handler event
      keypress: (event) => @handler event
      keyup: (event) => @handler event

    super extend defaults, options

    @push
      "blur": => @exit()

  active: ->
    document.activeElement and DomUtils.isFocusable document.activeElement

  handler: (event) ->
    if @active() then @stopBubblingAndTrue else @continueBubbling

  exit: () ->
    document.activeElement.blur() if @active()
    if @options.permanentInsertMode
      # We don't really exit if we're permanently installed.
      Mode.updateBadge()
    else
      super()

  chooseBadge: (badge) ->
    badge.badge ||= "I" if @active()

root = exports ? window
root.InsertMode = InsertMode

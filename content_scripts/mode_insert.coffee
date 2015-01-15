
class InsertMode extends Mode
  # There is one permanently-installed instance of InsertMode.  This allows PostFindMode to query the active
  # element.
  @permanentInstance: null

  constructor: (options = {}) ->
    InsertMode.permanentInstance ||= @
    @global = options.global

    defaults =
      name: "insert"
      keydown: (event) => @handleKeydownEvent event
      keypress: (event) => @handleKeyEvent event
      keyup: (event) => @handleKeyEvent event

    super extend defaults, options
    @insertModeLock = if options.targetElement? then options.targetElement else null

    @push
      "blur": (event) => @alwaysContinueBubbling =>
        if DomUtils.isFocusable event.target
          @exit event, event.target
          Mode.updateBadge()
      "focus": (event) => @alwaysContinueBubbling =>
        @insertModeLock = event.target if DomUtils.isFocusable event.target

    # We may already have focused an input element, so check.
    @insertModeLock = document.activeElement if document.activeElement and DomUtils.isEditable document.activeElement

  isActive: ->
    return true if @insertModeLock != null or @global
    # Some sites (e.g. inbox.google.com) change the contentEditable property on the fly (see #1245); and
    # unfortunately, the focus event fires *before* the change.  Therefore, we need to re-check whether the
    # active element is contentEditable.
    @insertModeLock = document.activeElement if document.activeElement?.isContentEditable
    @insertModeLock != null

  handleKeydownEvent: (event) ->
    return @continueBubbling if event == InsertMode.suppressedEvent or not @isActive()
    return @stopBubblingAndTrue unless KeyboardUtils.isEscape event
    DomUtils.suppressKeyupAfterEscape handlerStack
    @exit event, event.srcElement
    Mode.updateBadge()
    @suppressEvent

  # Handles keypress and keyup events.
  handleKeyEvent: (event) ->
    if @isActive() and event != InsertMode.suppressedEvent then @stopBubblingAndTrue else @continueBubbling

  exit: (_, target)  ->
    if target and (target == @insertModeLock or @global) and DomUtils.isFocusable target
      # Remove focus so the user can't just get himself back into insert mode by typing in the same input
      # box.
      # NOTE(smblott, 2014/12/22) Including embeds for .blur() etc. here is experimental.  It appears to be
      # the right thing to do for most common use cases.  However, it could also cripple flash-based sites and
      # games.  See discussion in #1211 and #1194.
      target.blur()
    if target == undefined or target == @insertModeLock or @global
      @insertModeLock = null
      # Now really exit, unless this is the permanently-installed instance.
      super() unless @ == InsertMode.permanentInstance

  chooseBadge: (badge) ->
    return if badge == InsertMode.suppressedEvent
    badge.badge ||= "I" if @isActive()

  # Static stuff to allow PostFindMode to suppress insert mode.
  @suppressedEvent: null
  @suppressEvent: (event) -> @suppressedEvent = event

root = exports ? window
root.InsertMode = InsertMode

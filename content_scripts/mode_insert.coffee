
class InsertMode extends Mode
  constructor: (options = {}) ->
    defaults =
      name: "insert"
      keydown: (event) => @handleKeydownEvent event
      keypress: (event) => @handleKeyEvent event
      keyup: (event) => @handleKeyEvent event

    super extend defaults, options
    @insertModeLock = if options.targetElement? then options.targetElement else null

    @push
      "blur": => @alwaysContinueBubbling =>
        if DomUtils.isFocusable event.target
          @exit event.target
          Mode.updateBadge()
      "focus": (event) => @alwaysContinueBubbling =>
        @insertModeLock = event.target if DomUtils.isFocusable event.target

    if @insertModeLock == null
      # We may already have focused an input element, so check.
      @insertModeLock = event.target if document.activeElement and DomUtils.isFocusable document.activeElement

  isActive: ->
    return true if @insertModeLock != null
    # Some sites (e.g. inbox.google.com) change the contentEditable property on the fly (see #1245); and
    # unfortunately, the focus event fires *before* the change.  Therefore, we need to re-check whether the
    # active element is contentEditable.
    @insertModeLock = document.activeElement if document.activeElement?.isContentEditable
    @insertModeLock != null

  handleKeydownEvent: (event) ->
    return @continueBubbling if event == InsertMode.suppressedEvent or not @isActive()
    return @stopBubblingAndTrue unless KeyboardUtils.isEscape event
    DomUtils.suppressKeyupAfterEscape handlerStack
    if DomUtils.isFocusable event.srcElement
      # Remove focus so the user can't just get himself back into insert mode by typing in the same input
      # box.
      # NOTE(smblott, 2014/12/22) Including embeds for .blur() etc. here is experimental.  It appears to be
      # the right thing to do for most common use cases.  However, it could also cripple flash-based sites and
      # games.  See discussion in #1211 and #1194.
      event.srcElement.blur()
    @exit()
    Mode.updateBadge()
    @suppressEvent

  # Handles keypress and keyup events.
  handleKeyEvent: (event) ->
    if @isActive() and event != InsertMode.suppressedEvent then @stopBubblingAndTrue else @continueBubbling

  exit: (target)  ->
    if target == undefined or target == @insertModeLock
      if @options.targetElement?
        super()
      else
        # If @options.targetElement isn't set, then this is the permanently-installed instance from the front
        # end.  So, we don't actually exit; instead, we just reset ourselves.
        @insertModeLock = null

  chooseBadge: (badge) ->
    badge.badge ||= "I" if @isActive()

  # Static stuff to allow PostFindMode to suppress insert mode.
  @suppressedEvent: null
  @suppressEvent: (event) -> @suppressedEvent = event

root = exports ? window
root.InsertMode = InsertMode


class InsertMode extends Mode
  # There is one permanently-installed instance of InsertMode.
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

    @insertModeLock =
      if document.activeElement and DomUtils.isEditable document.activeElement
        # We have already focused an input element, so use it.
        document.activeElement
      else
        null

    @push
      "blur": (event) => @alwaysContinueBubbling =>
        target = event.target
        # We can't rely on focus and blur events arriving in the expected order.  When the active element
        # changes, we might get "blur" before "focus".  The approach we take is to track the active element in
        # @insertModeLock, and exit only when the that element blurs.
        @exit event, target if target == @insertModeLock and DomUtils.isFocusable target
      "focus": (event) => @alwaysContinueBubbling =>
        if @insertModeLock != event.target and DomUtils.isFocusable event.target
          @insertModeLock = event.target
          Mode.updateBadge()

  isActive: ->
    return true if @insertModeLock or @global
    # Some sites (e.g. inbox.google.com) change the contentEditable property on the fly (see #1245); and
    # unfortunately, the focus event fires *before* the change.  Therefore, we need to re-check whether the
    # active element is contentEditable.
    if document.activeElement?.isContentEditable and @insertModeLock != document.activeElement
      @insertModeLock = document.activeElement
      Mode.updateBadge()
    @insertModeLock != null

  handleKeydownEvent: (event) ->
    return @continueBubbling if event == InsertMode.suppressedEvent or not @isActive()
    return @stopBubblingAndTrue unless KeyboardUtils.isEscape event
    DomUtils.suppressKeyupAfterEscape handlerStack
    @exit event, event.srcElement
    @suppressEvent

  # Handles keypress and keyup events.
  handleKeyEvent: (event) ->
    if @isActive() and event != InsertMode.suppressedEvent then @stopBubblingAndTrue else @continueBubbling

  exit: (_, target)  ->
    if (target and target == @insertModeLock) or @global or target == undefined
      @insertModeLock = null
      if target and DomUtils.isFocusable target
        # Remove the focus, so the user can't just get himself back into insert mode by typing in the same input
        # box.
        # NOTE(smblott, 2014/12/22) Including embeds for .blur() etc. here is experimental.  It appears to be
        # the right thing to do for most common use cases.  However, it could also cripple flash-based sites and
        # games.  See discussion in #1211 and #1194.
        target.blur()
      # Really exit, but only if this isn't the permanently-installed instance.
      if @ == InsertMode.permanentInstance then Mode.updateBadge() else super()

  chooseBadge: (badge) ->
    return if badge == InsertMode.suppressedEvent
    badge.badge ||= "I" if @isActive()

  # Static stuff to allow PostFindMode to suppress insert mode.
  @suppressedEvent: null
  @suppressEvent: (event) -> @suppressedEvent = event

root = exports ? window
root.InsertMode = InsertMode

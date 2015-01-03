
class InsertMode extends Mode
  insertModeActive: false
  insertModeLock: null

  # Input or text elements are considered focusable and able to receieve their own keyboard events, and will
  # enter insert mode if focused. Also note that the "contentEditable" attribute can be set on any element
  # which makes it a rich text editor, like the notes on jjot.com.
  isEditable: (element) ->
    return true if element.isContentEditable
    nodeName = element.nodeName?.toLowerCase()
    # Use a blacklist instead of a whitelist because new form controls are still being implemented for html5.
    if nodeName == "input" and element.type not in ["radio", "checkbox"]
      return true
    nodeName in ["textarea", "select"]

  # Embedded elements like Flash and quicktime players can obtain focus.
  isEmbed: (element) ->
    element.nodeName?.toLowerCase() in ["embed", "object"]

  isFocusable: (element) ->
    @isEditable(element) or @isEmbed element

  # Check whether insert mode is active.  Also, activate insert mode if the current element is content
  # editable (and the event is not suppressed).
  isActiveOrActivate: (event) ->
    return true if @insertModeActive
    return false if event.suppressKeydownTrigger
    # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245); and
    # unfortunately, isEditable() is called *before* the change is made.  Therefore, we need to re-check
    # whether the active element is contentEditable.
    @activate() if document.activeElement?.isContentEditable
    @insertModeActive

  activate: (target=null) ->
    unless @insertModeActive
      @insertModeActive = true
      @insertModeLock = target
      @badge = "I"
      Mode.updateBadge()

  deactivate: ->
    if @insertModeActive
      @insertModeActive = false
      @insertModeLock = null
      @badge = ""
      Mode.updateBadge()

  constructor: ->
    super
      name: "insert"
      keydown: (event) =>
        return @continueBubbling unless @isActiveOrActivate event
        return @stopBubblingAndTrue unless KeyboardUtils.isEscape event
        # We're in insert mode, and now exiting.
        if event.srcElement? and @isFocusable event.srcElement
          # Remove the focus so the user can't just get himself back into insert mode by typing in the same
          # input box.
          # NOTE(smblott, 2014/12/22) Including embeds for .blur() here is experimental.  It appears to be the
          # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
          # games.  See discussion in #1211 and #1194.
          event.srcElement.blur()
        @deactivate()
        @suppressEvent
      keypress: => if @insertModeActive then @stopBubblingAndTrue else @continueBubbling
      keyup: => if @insertModeActive then @stopBubblingAndTrue else @continueBubbling

    @handlers.push handlerStack.push
      focus: (event) =>
        handlerStack.alwaysContinueBubbling =>
          if not @insertModeActive and @isFocusable event.target
            @activate event.target
      blur: (event) =>
        handlerStack.alwaysContinueBubbling =>
          if @insertModeActive and event.target == @insertModeLock
            @deactivate()

    # We may already have focussed something, so check, so check.
    @activate document.activeElement if document.activeElement and @isFocusable document.activeElement

  # Used to prevent keydown events from triggering insert mode (following find).
  # FIXME(smblott)  This is a hack.
  @suppressKeydownTrigger: (event) ->
    event.suppressKeydownTrigger = true

# Activate this mode to prevent a focused, editable element from triggering insert mode.
class InsertModeSuppressFocusTrigger extends Mode
  constructor: ->
    super {name: "suppress-focus-trigger"}
    @handlers.push handlerStack.push
      focus: => @suppressEvent

root = exports ? window
root.InsertMode = InsertMode
root.InsertModeSuppressFocusTrigger = InsertModeSuppressFocusTrigger

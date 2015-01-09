class InsertMode extends Mode
  element: null

  constructor: (element, showIndicator = true) ->
    # Register listeners before calling the constructor, in case a mode we replace changes focus.
    document.addEventListener "focus", @onFocusCapturePhase, true
    document.addEventListener "blur", @onBlurCapturePhase, true

    super "INSERT", {}
    @activate element, showIndicator unless element == null

  destructor: ->
    document.removeEventListener "focus", @onFocusCapturePhase, true
    document.removeEventListener "blur", @onBlurCapturePhase, true

  keydown: (event) ->
    return false unless KeyboardUtils.isEscape event

    # Remove focus so the user can't just get himself back into insert mode by typing in the same input box.
    # NOTE(smblott, 2014/12/22) Including embeds for .blur() etc. here is experimental.  It appears to be the
    # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
    # games.  See discussion in #1211 and #1194.
    event.srcElement.blur() if DomUtils.isFocusable(event.srcElement)
    @deactivate()
    DomUtils.suppressEvent event
    KeydownEvents.push event
    false

  onFocusCapturePhase: (event) =>
    @activate event.target

  onBlurCapturePhase: (event) =>
    if DomUtils.isFocusable event.target
      @deactivate event.target

  isActive: ->
    @element != null or
    # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245); and
    # unfortunately, isEditable() is called *before* the change is made.  Therefore, we need to re-check
    # whether the active element is contentEditable.
      (document.activeElement?.isContentEditable and @activate document.activeElement)

  activate: (element, showIndicator = true) ->
    if element? and not DomUtils.isFocusable element
      return false # This element isn't one that uses insert mode.
    else if showIndicator
      HUD.show("Insert mode")

    @element = element
    true

  deactivate: (element) ->
    return unless @isActive
    # Only deactivate if the right element is given, or there's no element at all.
    if element == undefined or element == @element
      @element = null
      HUD.hide()
      false
    else
      true

root = exports ? window
root.InsertMode = InsertMode

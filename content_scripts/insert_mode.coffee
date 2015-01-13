# This implements insert mode.
#
# Insert mode can be activated in one of 2 ways:
# * Automatically, by focusing an editable element.
#   (NOTE: this requires that an inactive InsertMode instance is created when the document is loaded, via
#     new InsertMode(null, false, false)      )
# * By creating an instance of this class with
#     new InsertMode()
#
# To exit insert mode, use Mode.deactivate:
#   Mode.deactivate "INSERT"
#
# The constructor takes 3 arguments:
#  element          the element that insert mode applies to, or null if the user triggered insert mode
#                   manually
#  showIndicator    whether the HUD should be shown for this instance of insert mode
#  activate         whether this instance of insert mode should start activated.
#                   (NOTE: this should only be used to set up the event listeners on document load)
#
# Insert mode is *always* active when an editable element is focused.
# A mode that should only be active for an editable element can be implemented as a sub-mode of this, and
# will be automatically deactivated when the element is blurred.
# NOTE: The key{down,press,up} handlers for the sub-mode have to be explicitly called, and will not
# automatically attach to the document.
#
class InsertMode extends Mode
  element: null

  constructor: (element, showIndicator = false, activate = true) ->
    # Register listeners before calling the constructor, in case a mode we replace changes focus.
    document.addEventListener "focus", @onFocusCapturePhase, true
    document.addEventListener "blur", @onBlurCapturePhase, true

    super {name: "INSERT"}
    if activate
      @activate element, showIndicator unless element == null

  destructor: ->
    # Clean up event listeners; this instance is being replaced by another.
    document.removeEventListener "focus", @onFocusCapturePhase, true
    document.removeEventListener "blur", @onBlurCapturePhase, true

  keydown: (event) ->
    if @modes.INPUT_NORMAL?.isActive()
      # An input is focused, but we still want to handle keypresses as normal mode commands.
      @modes.INPUT_NORMAL.keydown event
      return Mode.handledEvent
    else unless KeyboardUtils.isEscape event
      return Mode.handledEvent

    # Remove focus so the user can't just get himself back into insert mode by typing in the same input box.
    # NOTE(smblott, 2014/12/22) Including embeds for .blur() etc. here is experimental.  It appears to be the
    # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
    # games.  See discussion in #1211 and #1194.
    event.srcElement.blur() if DomUtils.isFocusable(event.srcElement)
    @deactivate()
    Mode.suppressEvent

  keypress: (event) ->
    if @modes.INPUT_NORMAL?.isActive()
      # An input is focused, but we still want to handle keypresses as normal mode commands.
      @modes.INPUT_NORMAL.keypress event
    Mode.handledEvent

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

  activate: (element, showIndicator = false) ->
    if element? and not DomUtils.isFocusable element
      return false # This element isn't one that uses insert mode.
    else if showIndicator
      HUD.show("Insert mode")

    @element = element
    # We re-establish insert mode when the user clicks to fix #1414.
    reshowIndicator = showIndicator
    element?.addEventListener "click", reestablishInputModeOnClick, false
    true

  deactivate: (element) ->
    return unless @isActive()
    # Only deactivate if the right element is given, or there's no element at all.
    if element == undefined or element == @element
      element?.removeEventListener "click", reestablishInputModeOnClick, false
      @element = null
      HUD.hide()
      false
    else
      true

reshowIndicator = false
reestablishInputModeOnClick = -> new InsertMode event.target, reshowIndicator

root = exports ? window
root.InsertMode = InsertMode

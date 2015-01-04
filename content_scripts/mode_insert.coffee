
# Input or text elements are considered focusable and able to receieve their own keyboard events, and will
# enter insert mode if focused. Also note that the "contentEditable" attribute can be set on any element
# which makes it a rich text editor, like the notes on jjot.com.
isEditable =(element) ->
  return true if element.isContentEditable
  nodeName = element.nodeName?.toLowerCase()
  # Use a blacklist instead of a whitelist because new form controls are still being implemented for html5.
  if nodeName == "input" and element.type not in ["radio", "checkbox"]
    return true
  nodeName in ["textarea", "select"]

# Embedded elements like Flash and quicktime players can obtain focus.
isEmbed =(element) ->
  element.nodeName?.toLowerCase() in ["embed", "object"]

isFocusable =(element) ->
  isEditable(element) or isEmbed element

class InsertMode extends ConstrainedMode

  constructor: (@insertModeLock=null) ->
    super @insertModeLock, InsertMode,
      name: "insert"
      badge: "I"
      keydown: (event) => @stopBubblingAndTrue
      keypress: (event) => @stopBubblingAndTrue
      keyup: (event) => @stopBubblingAndTrue

    @push
      focus: (event, extra) =>
        handlerStack.alwaysContinueBubbling =>
          # Inform InsertModeTrigger that InsertMode is already active.
          extra.insertModeActive = true

    Mode.updateBadge()

  exit: (event=null) ->
    if event?.source == ExitOnEscapeMode and event?.event?.srcElement?
      element = event.event.srcElement
      if isFocusable element
        # Remove the focus so the user can't just get himself back into insert mode by typing in the same
        # input box.
        # NOTE(smblott, 2014/12/22) Including embeds for .blur() here is experimental.  It appears to be the
        # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
        # games.  See discussion in #1211 and #1194.
        element.blur()
    super()

# Trigger insert mode:
#   - On keydown event in a contentEditable element.
#   - When a focusable element receives the focus.
# Can be suppressed by setting extra.suppressInsertModeTrigger.
class InsertModeTrigger extends Mode
  constructor: ->
    super
      name: "insert-trigger"
      keydown: (event, extra) =>
        handlerStack.alwaysContinueBubbling =>
          unless extra.suppressInsertModeTrigger?
            # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245); and
            # unfortunately, isEditable() is called *before* the change is made.  Therefore, we need to check
            # whether the active element is contentEditable.
            new InsertMode() if document.activeElement?.isContentEditable

    @push
      focus: (event, extra) =>
        handlerStack.alwaysContinueBubbling =>
          unless extra.suppressInsertModeTrigger?
            new InsertMode event.target if isFocusable event.target

    # We may already have focussed something, so check.
    new InsertMode document.activeElement if document.activeElement and isFocusable document.activeElement

  @suppress: (extra) ->
    extra.suppressInsertModeTrigger = true

# Disables InsertModeTrigger.  Used by find mode to prevent unintentionally dropping into insert mode on
# focusable elements.
# If @element is provided, then don't block focus events, and block keydown events only on the indicated
# element.
class InsertModeBlocker extends SingletonMode
  constructor: (singleton=InsertModeBlocker, @element=null, options={}) ->
    options.name ||= "insert-blocker"
    super singleton, options

    unless @element?
      @push
        focus: (event, extra) =>
          handlerStack.alwaysContinueBubbling =>
            InsertModeTrigger.suppress extra

    if @element?.isContentEditable
      @push
        keydown: (event, extra) =>
          handlerStack.alwaysContinueBubbling =>
            InsertModeTrigger.suppress extra if event.srcElement == @element

root = exports ? window
root.InsertMode = InsertMode
root.InsertModeTrigger = InsertModeTrigger
root.InsertModeBlocker = InsertModeBlocker

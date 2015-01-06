
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

# This mode is installed when insert mode is active.
class InsertMode extends ConstrainedMode
  constructor: (@insertModeLock=null) ->
    super @insertModeLock, InsertMode,
      name: "insert"
      badge: "I"
      keydown: (event) => @stopBubblingAndTrue
      keypress: (event) => @stopBubblingAndTrue
      keyup: (event) => @stopBubblingAndTrue

  exit: (extra={}) ->
    super()
    if extra.source == ExitOnEscapeMode and extra.event?.srcElement?
      if isFocusable extra.event.srcElement
        # Remove the focus so the user can't just get himself back into insert mode by typing in the same
        # input box.
        # NOTE(smblott, 2014/12/22) Including embeds for .blur() here is experimental.  It appears to be the
        # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
        # games.  See discussion in #1211 and #1194.
        extra.event.srcElement.blur()

  # Static method. Return whether insert mode is currently active or not.
  @isActive: (singleton) -> SingletonMode.isActive InsertMode

# Trigger insert mode:
#   - On a keydown event in a contentEditable element.
#   - When a focusable element receives the focus.
#   - When an editable activeElement is clicked.  We cannot rely exclusively on focus events for triggering
#     insert mode.  With find mode, an editable element can be active, but we're not in insert mode (see
#     PostFindMode), and no focus event will be generated.  In this case, clicking on the element should
#     activate insert mode (even if the insert-mode blocker is active).
#
# This mode is permanently installed fairly low down on the handler stack.
class InsertModeTrigger extends Mode
  constructor: ->
    super
      name: "insert-trigger"
      keydown: (event, extra) =>
        @alwaysContinueBubbling =>
          unless InsertModeBlocker.isActive()
            # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245);
            # and unfortunately, the focus event happens *before* the change is made.  Therefore, we need to
            # check again whether the active element is contentEditable.
            new InsertMode document.activeElement if document.activeElement?.isContentEditable

    @push
      focus: (event, extra) =>
        @alwaysContinueBubbling =>
          unless InsertMode.isActive() or InsertModeBlocker.isActive()
            new InsertMode event.target if isFocusable event.target

      click: (event, extra) =>
        @alwaysContinueBubbling =>
          unless InsertMode.isActive()
            # We cannot check InsertModeBlocker.isActive().  PostFindMode exits on clicks, so will already have
            # gone.  So, instead, it sets an extra we can check.
            if extra?.postFindModeExited
              if document.activeElement == event.target and isEditable event.target
                new InsertMode event.target

    # We may already have focussed something, so check.
    new InsertMode document.activeElement if document.activeElement and isFocusable document.activeElement

# Disables InsertModeTrigger.  Used by find mode and findFocus to prevent unintentionally dropping into insert
# mode on focusable elements.
class InsertModeBlocker extends SingletonMode
  constructor: (element, options={}) ->
    options.name ||= "insert-blocker"
    super InsertModeBlocker, options

    @push
      "blur": (event) => @alwaysContinueBubbling => @exit() if element? and event.srcElement == element

  # Static method. Return whether the insert-mode blocker is currently active or not.
  @isActive: (singleton) -> SingletonMode.isActive InsertModeBlocker

root = exports ? window
root.InsertMode = InsertMode
root.InsertModeTrigger = InsertModeTrigger
root.InsertModeBlocker = InsertModeBlocker


# Install frontend event handlers.
initializeWhenEnabled()

installListener = (element, event, callback) ->
  element.addEventListener event, (-> callback.apply(this, arguments)), true

# A count of the number of keyboard events received by the page (for the most recently-sent keystroke).  E.g.,
# we expect 3 if the keystroke is passed through (keydown, keypress, keyup), and 0 if it is suppressed.
pageKeyboardEventCount = 0

sendKeyboardEvent = (key) ->
  pageKeyboardEventCount = 0
  response = window.callPhantom
    request: "keyboard"
    key: key

# These listeners receive events after the main frontend listeners, and do not receive suppressed events.
for type in [ "keydown", "keypress", "keyup" ]
  installListener window, type, (event) ->
    pageKeyboardEventCount += 1

# Some tests have side effects on the handler stack and the active mode, so these are reset on setup.
initializeModeState = ->
  Mode.reset()
  handlerStack.reset()
  initializeModes()
  # We use "m" as the only mapped key, "p" as a passkey, and "u" as an unmapped key.
  refreshCompletionKeys
    completionKeys: "mp"
  handlerStack.bubbleEvent "registerStateChange",
    enabled: true
    passKeys: "p"
  handlerStack.bubbleEvent "registerKeyQueue",
    keyQueue: ""

#
# Retrieve the hint markers as an array object.
#
getHintMarkers = ->
  Array::slice.call document.getElementsByClassName("vimiumHintMarker"), 0

#
# Generate tests that are common to both default and filtered
# link hinting modes.
#
createGeneralHintTests = (isFilteredMode) ->

  context "Link hints",

    setup ->
      initializeModeState()
      testContent = "<a>test</a>" + "<a>tress</a>"
      document.getElementById("test-div").innerHTML = testContent
      stub settings.values, "filterLinkHints", false
      stub settings.values, "linkHintCharacters", "ab"

    tearDown ->
      document.getElementById("test-div").innerHTML = ""

    should "create hints when activated, discard them when deactivated", ->
      LinkHints.activateMode()
      assert.isFalse not LinkHints.hintMarkerContainingDiv?
      LinkHints.deactivateMode()
      assert.isTrue not LinkHints.hintMarkerContainingDiv?

    should "position items correctly", ->
      assertStartPosition = (element1, element2) ->
        assert.equal element1.getClientRects()[0].left, element2.getClientRects()[0].left
        assert.equal element1.getClientRects()[0].top, element2.getClientRects()[0].top
      stub document.body, "style", "static"
      LinkHints.activateMode()
      hintMarkers = getHintMarkers()
      assertStartPosition document.getElementsByTagName("a")[0], hintMarkers[0]
      assertStartPosition document.getElementsByTagName("a")[1], hintMarkers[1]
      LinkHints.deactivateMode()
      stub document.body.style, "position", "relative"
      LinkHints.activateMode()
      hintMarkers = getHintMarkers()
      assertStartPosition document.getElementsByTagName("a")[0], hintMarkers[0]
      assertStartPosition document.getElementsByTagName("a")[1], hintMarkers[1]
      LinkHints.deactivateMode()

createGeneralHintTests false
createGeneralHintTests true

inputs = []
context "Test link hints for focusing input elements correctly",

  setup ->
    initializeModeState()
    testDiv = document.getElementById("test-div")
    testDiv.innerHTML = ""

    stub settings.values, "filterLinkHints", false
    stub settings.values, "linkHintCharacters", "ab"

    # Every HTML5 input type except for hidden. We should be able to activate all of them with link hints.
    inputTypes = ["button", "checkbox", "color", "date", "datetime", "datetime-local", "email", "file",
      "image", "month", "number", "password", "radio", "range", "reset", "search", "submit", "tel", "text",
      "time", "url", "week"]

    for type in inputTypes
      input = document.createElement "input"
      input.type = type
      testDiv.appendChild input
      inputs.push input

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "Focus each input when its hint text is typed", ->
    for input in inputs
      input.scrollIntoView() # Ensure the element is visible so we create a link hint for it.

      activeListener = ensureCalled (event) ->
        input.blur() if event.type == "focus"
      input.addEventListener "focus", activeListener, false
      input.addEventListener "click", activeListener, false

      LinkHints.activateMode()
      [hint] = getHintMarkers().filter (hint) -> input == hint.clickableItem
      sendKeyboardEvent char for char in hint.hintString

      input.removeEventListener "focus", activeListener, false
      input.removeEventListener "click", activeListener, false

context "Alphabetical link hints",

  setup ->
    initializeModeState()
    stub settings.values, "filterLinkHints", false
    stub settings.values, "linkHintCharacters", "ab"

    # Three hints will trigger double hint chars.
    createLinks 3
    LinkHints.init()
    LinkHints.activateMode()

  tearDown ->
    LinkHints.deactivateMode()
    document.getElementById("test-div").innerHTML = ""

  should "label the hints correctly", ->
    # TODO(philc): This test verifies the current behavior, but the current behavior is incorrect.
    # The output here should be something like aa, ab, b.
    hintMarkers = getHintMarkers()
    expectedHints = ["aa", "ba", "ab"]
    for hint, i in expectedHints
      assert.equal hint, hintMarkers[i].hintString

  should "narrow the hints", ->
    hintMarkers = getHintMarkers()
    sendKeyboardEvent "A"
    assert.equal "none", hintMarkers[1].style.display
    assert.equal "", hintMarkers[0].style.display

context "Filtered link hints",

  setup ->
    stub settings.values, "filterLinkHints", true
    stub settings.values, "linkHintNumbers", "0123456789"

  context "Text hints",

    setup ->
      initializeModeState()
      testContent = "<a>test</a>" + "<a>tress</a>" + "<a>trait</a>" + "<a>track<img alt='alt text'/></a>"
      document.getElementById("test-div").innerHTML = testContent
      LinkHints.init()
      LinkHints.activateMode()

    tearDown ->
      document.getElementById("test-div").innerHTML = ""
      LinkHints.deactivateMode()

    should "label the hints", ->
      hintMarkers = getHintMarkers()
      for i in [0...4]
        assert.equal (i + 1).toString(), hintMarkers[i].textContent.toLowerCase()

    should "narrow the hints", ->
      hintMarkers = getHintMarkers()
      sendKeyboardEvent "T"
      sendKeyboardEvent "R"
      assert.equal "none", hintMarkers[0].style.display
      assert.equal "1", hintMarkers[1].hintString
      assert.equal "", hintMarkers[1].style.display
      sendKeyboardEvent "A"
      assert.equal "2", hintMarkers[3].hintString

  context "Image hints",

    setup ->
      initializeModeState()
      testContent = "<a><img alt='alt text'/></a><a><img alt='alt text' title='some title'/></a>
        <a><img title='some title'/></a>" + "<a><img src='' width='320px' height='100px'/></a>"
      document.getElementById("test-div").innerHTML = testContent
      LinkHints.activateMode()

    tearDown ->
      document.getElementById("test-div").innerHTML = ""
      LinkHints.deactivateMode()

    should "label the images", ->
      hintMarkers = getHintMarkers()
      assert.equal "1: alt text", hintMarkers[0].textContent.toLowerCase()
      assert.equal "2: alt text", hintMarkers[1].textContent.toLowerCase()
      assert.equal "3: some title", hintMarkers[2].textContent.toLowerCase()
      assert.equal "4", hintMarkers[3].textContent.toLowerCase()

  context "Input hints",

    setup ->
      initializeModeState()
      testContent = "<input type='text' value='some value'/><input type='password' value='some value'/>
        <textarea>some text</textarea><label for='test-input'/>a label</label>
        <input type='text' id='test-input' value='some value'/>
        <label for='test-input-2'/>a label: </label><input type='text' id='test-input-2' value='some value'/>"
      document.getElementById("test-div").innerHTML = testContent
      LinkHints.activateMode()

    tearDown ->
      document.getElementById("test-div").innerHTML = ""
      LinkHints.deactivateMode()

    should "label the input elements", ->
      hintMarkers = getHintMarkers()
      assert.equal "1", hintMarkers[0].textContent.toLowerCase()
      assert.equal "2", hintMarkers[1].textContent.toLowerCase()
      assert.equal "3", hintMarkers[2].textContent.toLowerCase()
      assert.equal "4: a label", hintMarkers[3].textContent.toLowerCase()
      assert.equal "5: a label", hintMarkers[4].textContent.toLowerCase()

context "Input focus",

  setup ->
    initializeModeState()
    testContent = "<input type='text' id='first'/><input style='display:none;' id='second'/>
      <input type='password' id='third' value='some value'/>"
    document.getElementById("test-div").innerHTML = testContent

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "focus the first element", ->
    focusInput 1
    assert.equal "first", document.activeElement.id

  should "focus the nth element", ->
    focusInput 100
    assert.equal "third", document.activeElement.id

  should "activate insert mode on the first element", ->
    focusInput 1
    assert.isTrue InsertMode.permanentInstance.isActive()

  should "activate insert mode on the first element", ->
    focusInput 100
    assert.isTrue InsertMode.permanentInstance.isActive()

  should "activate the most recently-selected input if the count is 1", ->
    focusInput 3
    focusInput 1
    assert.equal "third", document.activeElement.id

  should "not trigger insert if there are no inputs", ->
    document.getElementById("test-div").innerHTML = ""
    focusInput 1
    assert.isFalse InsertMode.permanentInstance.isActive()

# TODO: these find prev/next link tests could be refactored into unit tests which invoke a function which has
# a tighter contract than goNext(), since they test minor aspects of goNext()'s link matching behavior, and we
# don't need to construct external state many times over just to test that.
# i.e. these tests should look something like:
# assert.equal(findLink(html("<a href=...">))[0].href, "first")
# These could then move outside of the dom_tests file.
context "Find prev / next links",

  setup ->
    initializeModeState()
    window.location.hash = ""

  should "find exact matches", ->
    document.getElementById("test-div").innerHTML = """
    <a href='#first'>nextcorrupted</a>
    <a href='#second'>next page</a>
    """
    stub settings.values, "nextPatterns", "next"
    goNext()
    assert.equal '#second', window.location.hash

  should "match against non-word patterns", ->
    document.getElementById("test-div").innerHTML = """
    <a href='#first'>&gt;&gt;</a>
    """
    stub settings.values, "nextPatterns", ">>"
    goNext()
    assert.equal '#first', window.location.hash

  should "favor matches with fewer words", ->
    document.getElementById("test-div").innerHTML = """
    <a href='#first'>lorem ipsum next</a>
    <a href='#second'>next!</a>
    """
    stub settings.values, "nextPatterns", "next"
    goNext()
    assert.equal '#second', window.location.hash

  should "find link relation in header", ->
    document.getElementById("test-div").innerHTML = """
    <link rel='next' href='#first'>
    """
    goNext()
    assert.equal '#first', window.location.hash

  should "favor link relation to text matching", ->
    document.getElementById("test-div").innerHTML = """
    <link rel='next' href='#first'>
    <a href='#second'>next</a>
    """
    goNext()
    assert.equal '#first', window.location.hash

  should "match mixed case link relation", ->
    document.getElementById("test-div").innerHTML = """
    <link rel='Next' href='#first'>
    """
    goNext()
    assert.equal '#first', window.location.hash

createLinks = (n) ->
  for i in [0...n] by 1
    link = document.createElement("a")
    link.textContent = "test"
    document.getElementById("test-div").appendChild link

context "Normal mode",
  setup ->
    initializeModeState()

  should "suppress mapped keys", ->
    sendKeyboardEvent "m"
    assert.equal pageKeyboardEventCount, 0

  should "not suppress unmapped keys", ->
    sendKeyboardEvent "u"
    assert.equal pageKeyboardEventCount, 3

  should "not suppress escape", ->
    sendKeyboardEvent "escape"
    assert.equal pageKeyboardEventCount, 2

  should "not suppress passKeys", ->
    sendKeyboardEvent "p"
    assert.equal pageKeyboardEventCount, 3

  should "suppress passKeys with a non-empty keyQueue", ->
    handlerStack.bubbleEvent "registerKeyQueue", keyQueue: "p"
    sendKeyboardEvent "p"
    assert.equal pageKeyboardEventCount, 0

context "Insert mode",
  setup ->
    initializeModeState()
    @insertMode = new InsertMode global: true

  should "not suppress mapped keys in insert mode", ->
    sendKeyboardEvent "m"
    assert.equal pageKeyboardEventCount, 3

  should "exit on escape", ->
    assert.isTrue @insertMode.modeIsActive
    sendKeyboardEvent "escape"
    assert.isFalse @insertMode.modeIsActive

  should "resume normal mode after leaving insert mode", ->
    @insertMode.exit()
    sendKeyboardEvent "m"
    assert.equal pageKeyboardEventCount, 0

context "Triggering insert mode",
  setup ->
    initializeModeState()

    testContent = "<input type='text' id='first'/>
      <input style='display:none;' id='second'/>
      <input type='password' id='third' value='some value'/>
      <p id='fourth' contenteditable='true'/>
      <p id='fifth'/>"
    document.getElementById("test-div").innerHTML = testContent

  tearDown ->
    document.activeElement?.blur()
    document.getElementById("test-div").innerHTML = ""

  should "trigger insert mode on focus of text input", ->
    assert.isFalse InsertMode.permanentInstance.isActive()
    document.getElementById("first").focus()
    assert.isTrue InsertMode.permanentInstance.isActive()

  should "trigger insert mode on focus of password input", ->
    assert.isFalse InsertMode.permanentInstance.isActive()
    document.getElementById("third").focus()
    assert.isTrue InsertMode.permanentInstance.isActive()

  should "trigger insert mode on focus of contentEditable elements", ->
    assert.isFalse InsertMode.permanentInstance.isActive()
    document.getElementById("fourth").focus()
    assert.isTrue InsertMode.permanentInstance.isActive()

  should "not trigger insert mode on other elements", ->
    assert.isFalse InsertMode.permanentInstance.isActive()
    document.getElementById("fifth").focus()
    assert.isFalse InsertMode.permanentInstance.isActive()

context "Mode utilities",
  setup ->
    initializeModeState()

    testContent = "<input type='text' id='first'/>
      <input style='display:none;' id='second'/>
      <input type='password' id='third' value='some value'/>"
    document.getElementById("test-div").innerHTML = testContent

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "not have duplicate singletons", ->
    count = 0

    class Test extends Mode
      constructor: -> count += 1; super singleton: Test
      exit: -> count -= 1; super()

    assert.isTrue count == 0
    for [1..10]
      mode = new Test()
      assert.isTrue count == 1

    mode.exit()
    assert.isTrue count == 0

  should "exit on escape", ->
    test = new Mode exitOnEscape: true

    assert.isTrue test.modeIsActive
    sendKeyboardEvent "escape"
    assert.equal pageKeyboardEventCount, 0
    assert.isFalse test.modeIsActive

  should "not exit on escape if not enabled", ->
    test = new Mode exitOnEscape: false

    assert.isTrue test.modeIsActive
    sendKeyboardEvent "escape"
    assert.equal pageKeyboardEventCount, 2
    assert.isTrue test.modeIsActive

  should "exit on blur", ->
    element = document.getElementById("first")
    element.focus()
    test = new Mode exitOnBlur: element

    assert.isTrue test.modeIsActive
    element.blur()
    assert.isFalse test.modeIsActive

  should "not exit on blur if not enabled", ->
    element = document.getElementById("first")
    element.focus()
    test = new Mode exitOnBlur: false

    assert.isTrue test.modeIsActive
    element.blur()
    assert.isTrue test.modeIsActive

  should "register state change", ->
    test = new Mode trackState: true
    handlerStack.bubbleEvent "registerStateChange", { enabled: "one", passKeys: "two" }

    assert.isTrue test.enabled == "one"
    assert.isTrue test.passKeys == "two"

  should "register the keyQueue", ->
    test = new Mode trackState: true
    handlerStack.bubbleEvent "registerKeyQueue", keyQueue: "hello"

    assert.isTrue test.keyQueue == "hello"

context "PostFindMode",
  setup ->
    initializeModeState()

    testContent = "<input type='text' id='first'/>"
    document.getElementById("test-div").innerHTML = testContent
    document.getElementById("first").focus()
    # For these tests, we need to push GrabBackFocus out of the way.  When it exits, it updates the badge,
    # which interferes with event suppression within insert mode.  This cannot happen in normal operation,
    # because GrabBackFocus exits on the first keydown.
    Mode.top().exit()
    @postFindMode = new PostFindMode

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "be a singleton", ->
    assert.isTrue @postFindMode.modeIsActive
    new PostFindMode
    assert.isFalse @postFindMode.modeIsActive

  should "suppress unmapped printable keys", ->
    sendKeyboardEvent "m"
    assert.equal 0, pageKeyboardEventCount

  should "be deactivated on click events", ->
    handlerStack.bubbleEvent "click", target: document.activeElement
    assert.isFalse @postFindMode.modeIsActive

  should "enter insert mode on immediate escape", ->
    sendKeyboardEvent "escape"
    assert.equal pageKeyboardEventCount, 0
    assert.isFalse @postFindMode.modeIsActive

  should "not enter insert mode on subsequent escapes", ->
    sendKeyboardEvent "a"
    sendKeyboardEvent "escape"
    assert.isTrue @postFindMode.modeIsActive

context "Mode badges",
  setup ->
    initializeModeState()
    testContent = "<input type='text' id='first'/>"
    document.getElementById("test-div").innerHTML = testContent

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "have no badge in normal mode", ->
    Mode.updateBadge()
    assert.isTrue chromeMessages[0].badge == ""

  should "have an I badge in insert mode by focus", ->
    document.getElementById("first").focus()
    # Focus triggers an event in the handler stack, so we check element "1", here.
    assert.isTrue chromeMessages[1].badge == "I"

  should "have no badge after leaving insert mode by focus", ->
    document.getElementById("first").focus()
    document.getElementById("first").blur()
    assert.isTrue chromeMessages[0].badge == ""

  should "have an I badge in global insert mode", ->
    new InsertMode global: true
    assert.isTrue chromeMessages[0].badge == "I"

  should "have no badge after leaving global insert mode", ->
    mode = new InsertMode global: true
    mode.exit()
    assert.isTrue chromeMessages[0].badge == ""

  should "have a ? badge in PostFindMode (immediately)", ->
    document.getElementById("first").focus()
    new PostFindMode
    assert.isTrue chromeMessages[0].badge == "?"

  should "have no badge in PostFindMode (subsequently)", ->
    document.getElementById("first").focus()
    new PostFindMode
    sendKeyboardEvent "a"
    assert.isTrue chromeMessages[0].badge == ""

  should "have no badge when disabled", ->
    handlerStack.bubbleEvent "registerStateChange",
      enabled: false
      passKeys: ""

    document.getElementById("first").focus()
    # Focus triggers an event in the handler stack, so we check element "1", here.
    assert.isTrue chromeMessages[1].badge == ""


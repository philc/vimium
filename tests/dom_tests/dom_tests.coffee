window.vimiumDomTestsAreRunning = true

# Install frontend event handlers.
HUD.init()
Frame.registerFrameId chromeFrameId: 0

getSelection = ->
  window.getSelection().toString()

commandName = commandCount = null

# Some tests have side effects on the handler stack and the active mode, so these are reset on setup.  Also,
# some tests affect the focus (e.g. Vomnibar tests), so we make sure the window has the focus.
initializeModeState = ->
  window.focus()
  Mode.reset()
  handlerStack.reset()
  normalMode = installModes()
  normalMode.setPassKeys "p"
  normalMode.setKeyMapping
    m: options: {}, command: "m" # A mapped key.
    p: options: {}, command: "p" # A pass key.
    z:
      p: options: {}, command: "zp" # Not a pass key.
  normalMode.setCommandHandler ({command, count}) ->
    [commandName, commandCount] = [command.command, count]
  commandName = commandCount = null
  normalMode # Return this.

# Tell Settings that it's been loaded.
Settings.isLoaded = true

# Shoulda.js doesn't support async code, so we try not to use any.
Utils.nextTick = (func) -> func()

#
# Retrieve the hint markers as an array object.
#
getHintMarkers = ->
  Array::slice.call document.getElementsByClassName("vimiumHintMarker"), 0

stubSettings = (key, value) -> stub Settings.cache, key, JSON.stringify value

HintCoordinator.sendMessage = (name, request = {}) -> HintCoordinator[name]? request; request
activateLinkHintsMode = ->
  HintCoordinator.getHintDescriptors modeIndex: 0
  HintCoordinator.activateMode hintDescriptors: {}, modeIndex: 0, originatingFrameId: frameId,

#
# Generate tests that are common to both default and filtered
# link hinting modes.
#
createGeneralHintTests = (isFilteredMode) ->
  window.vimiumOnClickAttributeName = "does-not-matter"

  context "Link hints",

    setup ->
      initializeModeState()
      testContent = "<a>test</a>" + "<a>tress</a>"
      document.getElementById("test-div").innerHTML = testContent
      stubSettings "filterLinkHints", isFilteredMode
      stubSettings "linkHintCharacters", "ab"
      stubSettings "linkHintNumbers", "12"
      stub window, "windowIsFocused", -> true

    tearDown ->
      document.getElementById("test-div").innerHTML = ""

    should "create hints when activated, discard them when deactivated", ->
      linkHints = activateLinkHintsMode()
      assert.isFalse not linkHints.hintMarkerContainingDiv?
      linkHints.deactivateMode()
      assert.isTrue not linkHints.hintMarkerContainingDiv?

    should "position items correctly", ->
      assertStartPosition = (element1, element2) ->
        assert.equal element1.getClientRects()[0].left, element2.getClientRects()[0].left
        assert.equal element1.getClientRects()[0].top, element2.getClientRects()[0].top
      stub document.body.style, "position", "static"
      linkHints = activateLinkHintsMode()
      hintMarkers = getHintMarkers()
      assertStartPosition document.getElementsByTagName("a")[0], hintMarkers[0]
      assertStartPosition document.getElementsByTagName("a")[1], hintMarkers[1]
      linkHints.deactivateMode()
      stub document.body.style, "position", "relative"
      linkHints = activateLinkHintsMode()
      hintMarkers = getHintMarkers()
      assertStartPosition document.getElementsByTagName("a")[0], hintMarkers[0]
      assertStartPosition document.getElementsByTagName("a")[1], hintMarkers[1]
      linkHints.deactivateMode()

createGeneralHintTests false
createGeneralHintTests true

context "False positives in link-hint",

  setup ->
    testContent = '<span class="buttonWrapper">false positive<a>clickable</a></span>' + '<span class="buttonWrapper">clickable</span>'
    document.getElementById("test-div").innerHTML = testContent
    stubSettings "filterLinkHints", true
    stubSettings "linkHintNumbers", "12"
    stub window, "windowIsFocused", -> true

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "handle false positives", ->
    linkHints = activateLinkHintsMode()
    hintMarkers = getHintMarkers()
    linkHints.deactivateMode()
    assert.equal 2, hintMarkers.length
    for hintMarker in hintMarkers
      assert.equal "clickable", hintMarker.linkText

context "jsaction matching",

  setup ->
    stubSettings "filterLinkHints", true
    testContent = '<p id="test-paragraph">clickable</p>'
    document.getElementById("test-div").innerHTML = testContent
    @element = document.getElementById("test-paragraph")

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "select jsaction elements", ->
    for text in ["click:namespace.actionName", "namespace.actionName"]
      @element.setAttribute "jsaction", text
      linkHints = activateLinkHintsMode()
      hintMarkers = getHintMarkers().filter (marker) -> marker.linkText != "Frame."
      linkHints.deactivateMode()
      assert.equal 1, hintMarkers.length
      assert.equal "clickable", hintMarkers[0].linkText
      assert.equal @element, hintMarkers[0].localHintDescriptor.element

  should "not select inactive jsaction elements", ->
    for text in ["mousedown:namespace.actionName", "click:namespace._", "none", "namespace:_"]
      @element.setAttribute "jsaction", text
      linkHints = activateLinkHintsMode()
      hintMarkers = getHintMarkers().filter (marker) -> marker.linkText != "Frame."
      linkHints.deactivateMode()
      assert.equal 0, hintMarkers.length

sendKeyboardEvent = (key, type="keydown", extra={}) ->
  handlerStack.bubbleEvent type, extend extra,
    type: type
    key: key
    preventDefault: ->
    stopImmediatePropagation: ->

sendKeyboardEvents = (keys) ->
  sendKeyboardEvent key for key in keys.split ""

inputs = []
context "Test link hints for focusing input elements correctly",

  setup ->
    initializeModeState()
    testDiv = document.getElementById("test-div")
    testDiv.innerHTML = ""

    stubSettings "filterLinkHints", false
    stubSettings "linkHintCharacters", "ab"

    # Every HTML5 input type except for hidden. We should be able to activate all of them with link hints.
    #
    # TODO: Re-insert "color" into the inputTypes list when PhantomJS issue #13979 is fixed and integrated.
    # Ref: https://github.com/ariya/phantomjs/issues/13979, and Vimium #1944.
    inputTypes = ["button", "checkbox", "date", "datetime", "datetime-local", "email", "file",
      "image", "month", "number", "password", "radio", "range", "reset", "search", "submit", "tel", "text",
      "time", "url", "week"]

    for type in inputTypes
      input = document.createElement "input"
      input.type = type
      testDiv.appendChild input
      inputs.push input

    # Manually add also a select element to test focus.
    input = document.createElement "select"
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

      activateLinkHintsMode()
      [hint] = getHintMarkers().filter (hint) ->
        input == HintCoordinator.getLocalHintMarker(hint.hintDescriptor).element
      sendKeyboardEvent char for char in hint.hintString

      input.removeEventListener "focus", activeListener, false
      input.removeEventListener "click", activeListener, false

context "Test link hints for changing mode",

  setup ->
    initializeModeState()
    testDiv = document.getElementById("test-div")
    testDiv.innerHTML = "<a>link</a>"
    @linkHints = activateLinkHintsMode()

  tearDown ->
    document.getElementById("test-div").innerHTML = ""
    @linkHints.deactivateMode()

  should "change mode on shift", ->
    assert.equal "curr-tab", @linkHints.mode.name
    sendKeyboardEvent "Shift", "keydown"
    assert.equal "bg-tab", @linkHints.mode.name
    sendKeyboardEvent "Shift", "keyup"
    assert.equal "curr-tab", @linkHints.mode.name

  should "change mode on ctrl", ->
    assert.equal "curr-tab", @linkHints.mode.name
    sendKeyboardEvent "Control", "keydown"
    assert.equal "fg-tab", @linkHints.mode.name
    sendKeyboardEvent "Control", "keyup"
    assert.equal "curr-tab", @linkHints.mode.name

context "Alphabetical link hints",

  setup ->
    initializeModeState()
    stubSettings "filterLinkHints", false
    stubSettings "linkHintCharacters", "ab"
    stub window, "windowIsFocused", -> true

    document.getElementById("test-div").innerHTML = ""
    # Three hints will trigger double hint chars.
    createLinks 3
    @linkHints = activateLinkHintsMode()

  tearDown ->
    @linkHints.deactivateMode()
    document.getElementById("test-div").innerHTML = ""

  should "label the hints correctly", ->
    hintMarkers = getHintMarkers()
    expectedHints = ["aa", "b", "ab"]
    assert.equal 3, hintMarkers.length
    for hint, i in expectedHints
      assert.equal hint, hintMarkers[i].hintString

  should "narrow the hints", ->
    hintMarkers = getHintMarkers()
    sendKeyboardEvent "a"
    assert.equal "none", hintMarkers[1].style.display
    assert.equal "", hintMarkers[0].style.display

  should "generate the correct number of alphabet hints", ->
    alphabetHints = new AlphabetHints
    for n in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      hintStrings = alphabetHints.hintStrings n
      assert.equal n, hintStrings.length

  should "generate non-overlapping alphabet hints", ->
    alphabetHints = new AlphabetHints
    for n in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      hintStrings = alphabetHints.hintStrings n
      for h1 in hintStrings
        for h2 in hintStrings
          unless h1 == h2
            assert.isFalse 0 == h1.indexOf h2

context "Filtered link hints",
  # Note.  In all of these tests, the order of the elements returned by getHintMarkers() may be different from
  # the order they are listed in the test HTML content.  This is because LinkHints.activateMode() sorts the
  # elements.

  setup ->
    stubSettings "filterLinkHints", true
    stubSettings "linkHintNumbers", "0123456789"
    stub window, "windowIsFocused", -> true

  context "Text hints",

    setup ->
      initializeModeState()
      testContent = "<a>test</a>" + "<a>tress</a>" + "<a>trait</a>" + "<a>track<img alt='alt text'/></a>"
      document.getElementById("test-div").innerHTML = testContent
      @linkHints = activateLinkHintsMode()

    tearDown ->
      document.getElementById("test-div").innerHTML = ""
      @linkHints.deactivateMode()

    should "label the hints", ->
      hintMarkers = getHintMarkers()
      expectedMarkers = [1..4].map (m) -> m.toString()
      actualMarkers = [0...4].map (i) -> hintMarkers[i].textContent.toLowerCase()
      assert.equal expectedMarkers.length, actualMarkers.length
      for marker in expectedMarkers
        assert.isTrue marker in actualMarkers

    should "narrow the hints", ->
      hintMarkers = getHintMarkers()
      sendKeyboardEvent "t"
      sendKeyboardEvent "r"
      assert.equal "none", hintMarkers[0].style.display
      assert.equal "3", hintMarkers[1].hintString
      assert.equal "", hintMarkers[1].style.display
      sendKeyboardEvent "a"
      assert.equal "1", hintMarkers[3].hintString

    # This test is the same as above, but with an extra non-matching character.  The effect should be the
    # same.
    should "narrow the hints and ignore typing mistakes", ->
      hintMarkers = getHintMarkers()
      sendKeyboardEvent "t"
      sendKeyboardEvent "r"
      sendKeyboardEvent "x"
      assert.equal "none", hintMarkers[0].style.display
      assert.equal "3", hintMarkers[1].hintString
      assert.equal "", hintMarkers[1].style.display
      sendKeyboardEvent "a"
      assert.equal "1", hintMarkers[3].hintString

  context "Image hints",

    setup ->
      initializeModeState()
      testContent = "<a><img alt='alt text'/></a><a><img alt='alt text' title='some title'/></a>
        <a><img title='some title'/></a>" + "<a><img src='' width='320px' height='100px'/></a>"
      document.getElementById("test-div").innerHTML = testContent
      @linkHints = activateLinkHintsMode()

    tearDown ->
      document.getElementById("test-div").innerHTML = ""
      @linkHints.deactivateMode()

    should "label the images", ->
      hintMarkers = getHintMarkers().map (marker) -> marker.textContent.toLowerCase()
      # We don't know the actual hint numbers which will be assigned, so we replace them with "N".
      hintMarkers = hintMarkers.map (str) -> str.replace /^[1-4]/, "N"
      assert.equal 4, hintMarkers.length
      assert.isTrue "N: alt text" in hintMarkers
      assert.isTrue "N: some title" in hintMarkers
      assert.isTrue "N: alt text" in hintMarkers
      assert.isTrue "N" in hintMarkers

  context "Input hints",

    setup ->
      initializeModeState()
      testContent = "<input type='text' value='some value'/><input type='password' value='some value'/>
        <textarea>some text</textarea><label for='test-input'/>a label</label>
        <input type='text' id='test-input' value='some value'/>
        <label for='test-input-2'/>a label: </label><input type='text' id='test-input-2' value='some value'/>"
      document.getElementById("test-div").innerHTML = testContent
      @linkHints = activateLinkHintsMode()

    tearDown ->
      document.getElementById("test-div").innerHTML = ""
      @linkHints.deactivateMode()

    should "label the input elements", ->
      hintMarkers = getHintMarkers()
      hintMarkers = getHintMarkers().map (marker) -> marker.textContent.toLowerCase()
      # We don't know the actual hint numbers which will be assigned, so we replace them with "N".
      hintMarkers = hintMarkers.map (str) -> str.replace /^[0-9]+/, "N"
      assert.equal 5, hintMarkers.length
      assert.isTrue "N" in hintMarkers
      assert.isTrue "N" in hintMarkers
      assert.isTrue "N: a label" in hintMarkers
      assert.isTrue "N: a label" in hintMarkers
      assert.isTrue "N" in hintMarkers

  context "Text hint scoring",

    setup ->
      initializeModeState()
      testContent = [
        {id: 0, text: "the xboy stood on the xburning deck"} # Noise.
        {id: 1, text: "the boy stood on the xburning deck"}  # Whole word (boy).
        {id: 2, text: "on the xboy stood the xburning deck"} # Start of text (on).
        {id: 3, text: "the xboy stood on the xburning deck"} # Noise.
        {id: 4, text: "the xboy stood on the xburning deck"} # Noise.
        {id: 5, text: "the xboy stood on the xburning"}      # Shortest text..
        {id: 6, text: "the xboy stood on the burning xdeck"} # Start of word (bu)
        {id: 7, text: "test abc one - longer"}               # For tab test - 2.
        {id: 8, text: "test abc one"}                        # For tab test - 1.
        {id: 9, text: "test abc one - longer still"}         # For tab test - 3.
      ].map(({id,text}) -> "<a id=\"#{id}\">#{text}</a>").join " "
      document.getElementById("test-div").innerHTML = testContent
      @linkHints = activateLinkHintsMode()
      @getActiveHintMarker = ->
        HintCoordinator.getLocalHintMarker(@linkHints.markerMatcher.activeHintMarker.hintDescriptor).element.id

    tearDown ->
      document.getElementById("test-div").innerHTML = ""
      @linkHints.deactivateMode()

    should "score start-of-word matches highly", ->
      sendKeyboardEvents "bu"
      assert.equal "6", @getActiveHintMarker()

    should "score start-of-text matches highly (br)", ->
      sendKeyboardEvents "on"
      assert.equal "2", @getActiveHintMarker()

    should "score whole-word matches highly", ->
      sendKeyboardEvents "boy"
      assert.equal "1", @getActiveHintMarker()

    should "score shorter texts more highly", ->
      sendKeyboardEvents "stood"
      assert.equal "5", @getActiveHintMarker()

    should "use tab to select the active hint", ->
      sendKeyboardEvents "abc"
      assert.equal "8", @getActiveHintMarker()
      sendKeyboardEvent "Tab", "keydown"
      assert.equal "7", @getActiveHintMarker()
      sendKeyboardEvent "Tab", "keydown"
      assert.equal "9", @getActiveHintMarker()

context "Input focus",

  setup ->
    initializeModeState()
    testContent = "<input type='text' id='first'/><input style='display:none;' id='second'/>
      <input type='password' id='third' value='some value'/>"
    document.getElementById("test-div").innerHTML = testContent

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "focus the first element", ->
    NormalModeCommands.focusInput 1
    assert.equal "first", document.activeElement.id

  should "focus the nth element", ->
    NormalModeCommands.focusInput 100
    assert.equal "third", document.activeElement.id

  should "activate insert mode on the first element", ->
    NormalModeCommands.focusInput 1
    assert.isTrue InsertMode.permanentInstance.isActive()

  should "activate insert mode on the first element", ->
    NormalModeCommands.focusInput 100
    assert.isTrue InsertMode.permanentInstance.isActive()

  should "activate the most recently-selected input if the count is 1", ->
    NormalModeCommands.focusInput 3
    NormalModeCommands.focusInput 1
    assert.equal "third", document.activeElement.id

  should "not trigger insert if there are no inputs", ->
    document.getElementById("test-div").innerHTML = ""
    NormalModeCommands.focusInput 1
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
    stubSettings "nextPatterns", "next"
    NormalModeCommands.goNext()
    assert.equal '#second', window.location.hash

  should "match against non-word patterns", ->
    document.getElementById("test-div").innerHTML = """
    <a href='#first'>&gt;&gt;</a>
    """
    stubSettings "nextPatterns", ">>"
    NormalModeCommands.goNext()
    assert.equal '#first', window.location.hash

  should "favor matches with fewer words", ->
    document.getElementById("test-div").innerHTML = """
    <a href='#first'>lorem ipsum next</a>
    <a href='#second'>next!</a>
    """
    stubSettings "nextPatterns", "next"
    NormalModeCommands.goNext()
    assert.equal '#second', window.location.hash

  should "find link relation in header", ->
    document.getElementById("test-div").innerHTML = """
    <link rel='next' href='#first'>
    """
    NormalModeCommands.goNext()
    assert.equal '#first', window.location.hash

  should "favor link relation to text matching", ->
    document.getElementById("test-div").innerHTML = """
    <link rel='next' href='#first'>
    <a href='#second'>next</a>
    """
    NormalModeCommands.goNext()
    assert.equal '#first', window.location.hash

  should "match mixed case link relation", ->
    document.getElementById("test-div").innerHTML = """
    <link rel='Next' href='#first'>
    """
    NormalModeCommands.goNext()
    assert.equal '#first', window.location.hash

createLinks = (n) ->
  for i in [0...n] by 1
    link = document.createElement("a")
    link.textContent = "test"
    document.getElementById("test-div").appendChild link

context "Key mapping",
  setup ->
    @normalMode = initializeModeState()
    @handlerCalled = false
    @handlerCalledCount = 0
    @normalMode.setCommandHandler ({count}) =>
      @handlerCalled = true
      @handlerCalledCount = count

  should "recognize first mapped key", ->
    assert.isTrue @normalMode.isMappedKey "m"

  should "recognize second mapped key", ->
    assert.isFalse @normalMode.isMappedKey "p"
    sendKeyboardEvent "z"
    assert.isTrue @normalMode.isMappedKey "p"

  should "recognize pass keys", ->
    assert.isTrue @normalMode.isPassKey "p"

  should "not mis-recognize pass keys", ->
    assert.isFalse @normalMode.isMappedKey "p"
    sendKeyboardEvent "z"
    assert.isTrue @normalMode.isMappedKey "p"

  should "recognize initial count keys", ->
    assert.isTrue @normalMode.isCountKey "1"
    assert.isTrue @normalMode.isCountKey "9"

  should "not recognize '0' as initial count key", ->
    assert.isFalse @normalMode.isCountKey "0"

  should "recognize subsequent count keys", ->
    sendKeyboardEvent "1"
    assert.isTrue @normalMode.isCountKey "0"
    assert.isTrue @normalMode.isCountKey "9"

  should "set and call command handler", ->
    sendKeyboardEvent "m"
    assert.isTrue @handlerCalled

  should "not call command handler for pass keys", ->
    sendKeyboardEvent "p"
    assert.isFalse @handlerCalled

  should "accept a count prefix with a single digit", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "m"
    assert.equal 2, @handlerCalledCount

  should "accept a count prefix with multiple digits", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "0"
    sendKeyboardEvent "m"
    assert.equal 20, @handlerCalledCount

  should "cancel a count prefix", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "z"
    sendKeyboardEvent "m"
    assert.equal 1, @handlerCalledCount

  should "accept a count prefix for multi-key command mappings", ->
    sendKeyboardEvent "5"
    sendKeyboardEvent "z"
    sendKeyboardEvent "p"
    assert.equal 5, @handlerCalledCount

  should "cancel a key prefix", ->
    sendKeyboardEvent "z"
    sendKeyboardEvent "m"
    assert.equal 1, @handlerCalledCount

  should "cancel a count prefix after a prefix key", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "z"
    sendKeyboardEvent "m"
    assert.equal 1, @handlerCalledCount

  should "cancel a prefix key on escape", ->
    sendKeyboardEvent "z"
    sendKeyboardEvent "Escape", "keydown"
    sendKeyboardEvent "p"
    assert.equal 0, @handlerCalledCount

context "Normal mode",
  setup ->
    initializeModeState()

  should "invoke commands for mapped keys", ->
    sendKeyboardEvent "m"
    assert.equal "m", commandName

  should "invoke commands for mapped keys with a mapped prefix", ->
    sendKeyboardEvent "z"
    sendKeyboardEvent "m"
    assert.equal "m", commandName

  should "invoke commands for mapped keys with an unmapped prefix", ->
    sendKeyboardEvent "a"
    sendKeyboardEvent "m"
    assert.equal "m", commandName

  should "not invoke commands for pass keys", ->
    sendKeyboardEvent "p"
    assert.equal null, commandName

  should "not invoke commands for pass keys with an unmapped prefix", ->
    sendKeyboardEvent "a"
    sendKeyboardEvent "p"
    assert.equal null, commandName

  should "invoke commands for pass keys with a count", ->
    sendKeyboardEvent "1"
    sendKeyboardEvent "p"
    assert.equal "p", commandName

  should "invoke commands for pass keys with a key queue", ->
    sendKeyboardEvent "z"
    sendKeyboardEvent "p"
    assert.equal "zp", commandName

  should "default to a count of 1", ->
    sendKeyboardEvent "m"
    assert.equal 1, commandCount

  should "accept count prefixes of length 1", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "m"
    assert.equal 2, commandCount

  should "accept count prefixes of length 2", ->
    sendKeyboardEvents "12"
    sendKeyboardEvent "m"
    assert.equal 12, commandCount

  should "get the correct count for mixed inputs (single key)", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "z"
    sendKeyboardEvent "m"
    assert.equal 1, commandCount

  should "get the correct count for mixed inputs (multi key)", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "z"
    sendKeyboardEvent "p"
    assert.equal 2, commandCount

  should "get the correct count for mixed inputs (multi key, duplicates)", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "z"
    sendKeyboardEvent "z"
    sendKeyboardEvent "p"
    assert.equal 1, commandCount

  should "get the correct count for mixed inputs (with leading mapped keys)", ->
    sendKeyboardEvent "z"
    sendKeyboardEvent "2"
    sendKeyboardEvent "m"
    assert.equal 2, commandCount

  should "get the correct count for mixed inputs (with leading unmapped keys)", ->
    sendKeyboardEvent "a"
    sendKeyboardEvent "2"
    sendKeyboardEvent "m"
    assert.equal 2, commandCount

  should "not get a count after unmapped keys", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "a"
    sendKeyboardEvent "m"
    assert.equal 1, commandCount

  should "get the correct count after unmapped keys", ->
    sendKeyboardEvent "2"
    sendKeyboardEvent "a"
    sendKeyboardEvent "3"
    sendKeyboardEvent "m"
    assert.equal 3, commandCount

  should "not handle unmapped keys", ->
    sendKeyboardEvent "u"
    assert.equal null, commandCount

context "Insert mode",
  setup ->
    initializeModeState()
    @insertMode = new InsertMode global: true

  should "exit on escape", ->
    assert.isTrue @insertMode.modeIsActive
    sendKeyboardEvent "Escape", "keydown"
    assert.isFalse @insertMode.modeIsActive

  should "resume normal mode after leaving insert mode", ->
    assert.equal null, commandCount
    @insertMode.exit()
    sendKeyboardEvent "m"
    assert.equal 1, commandCount

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

context "Caret mode",
  setup ->
    document.getElementById("test-div").innerHTML = """
    <p><pre>
      It is an ancient Mariner,
      And he stoppeth one of three.
      By thy long grey beard and glittering eye,
      Now wherefore stopp'st thou me?
    </pre></p>
    """
    initializeModeState()
    @initialVisualMode = new VisualMode

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "enter caret mode", ->
    assert.isFalse @initialVisualMode.modeIsActive
    assert.equal "I", getSelection()

  should "exit caret mode on escape", ->
    sendKeyboardEvent "Escape", "keydown"
    assert.equal "", getSelection()

  should "move caret with l and h", ->
    assert.equal "I", getSelection()
    sendKeyboardEvent "l"
    assert.equal "t", getSelection()
    sendKeyboardEvent "h"
    assert.equal "I", getSelection()

  should "move caret with w and b", ->
    assert.equal "I", getSelection()
    sendKeyboardEvent "w"
    assert.equal "i", getSelection()
    sendKeyboardEvent "b"
    assert.equal "I", getSelection()

  should "move caret with e", ->
    assert.equal "I", getSelection()
    sendKeyboardEvent "e"
    assert.equal " ", getSelection()
    sendKeyboardEvent "e"
    assert.equal " ", getSelection()

  should "move caret with j and k", ->
    assert.equal "I", getSelection()
    sendKeyboardEvent "j"
    assert.equal "A", getSelection()
    sendKeyboardEvent "k"
    assert.equal "I", getSelection()

  should "re-use an existing selection", ->
    assert.equal "I", getSelection()
    sendKeyboardEvents "ww"
    assert.equal "a", getSelection()
    sendKeyboardEvent "Escape", "keydown"
    new VisualMode
    assert.equal "a", getSelection()

  should "not move the selection on caret/visual mode toggle", ->
    sendKeyboardEvents "ww"
    assert.equal "a", getSelection()
    for key in "vcvcvc".split()
      sendKeyboardEvent key
      assert.equal "a", getSelection()

context "Visual mode",
  setup ->
    document.getElementById("test-div").innerHTML = """
    <p><pre>
      It is an ancient Mariner,
      And he stoppeth one of three.
      By thy long grey beard and glittering eye,
      Now wherefore stopp'st thou me?
    </pre></p>
    """
    initializeModeState()
    @initialVisualMode = new VisualMode
    sendKeyboardEvent "w"
    sendKeyboardEvent "w"
    # We should now be at the "a" of "an".
    sendKeyboardEvent "v"

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "select word with e", ->
    assert.equal "a", getSelection()
    sendKeyboardEvent "e"
    assert.equal "an", getSelection()
    sendKeyboardEvent "e"
    assert.equal "an ancient", getSelection()

  should "select opposite end of the selection with o", ->
    assert.equal "a", getSelection()
    sendKeyboardEvent "e"
    assert.equal "an", getSelection()
    sendKeyboardEvent "e"
    assert.equal "an ancient", getSelection()
    sendKeyboardEvents "ow"
    assert.equal "ancient", getSelection()
    sendKeyboardEvents "oe"
    assert.equal "ancient Mariner", getSelection()

  should "accept a count", ->
    assert.equal "a", getSelection()
    sendKeyboardEvents "2e"
    assert.equal "an ancient", getSelection()

  should "select a word", ->
    assert.equal "a", getSelection()
    sendKeyboardEvents "aw"
    assert.equal "an", getSelection()

  should "select a word with a count", ->
    assert.equal "a", getSelection()
    sendKeyboardEvents "2aw"
    assert.equal "an ancient", getSelection()

  should "select a word with a count", ->
    assert.equal "a", getSelection()
    sendKeyboardEvents "2aw"
    assert.equal "an ancient", getSelection()

  should "select to start of line", ->
    assert.equal "a", getSelection()
    sendKeyboardEvents "0"
    assert.equal "It is", getSelection().trim()

  should "select to end of line", ->
    assert.equal "a", getSelection()
    sendKeyboardEvents "$"
    assert.equal "an ancient Mariner,", getSelection()

  should "re-enter caret mode", ->
    assert.equal "a", getSelection()
    sendKeyboardEvents "cww"
    assert.equal "M", getSelection()

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
      constructor: -> count += 1; super singleton: "test"
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
    sendKeyboardEvent "Escape", "keydown"
    assert.isFalse test.modeIsActive

  should "not exit on escape if not enabled", ->
    test = new Mode exitOnEscape: false

    assert.isTrue test.modeIsActive
    sendKeyboardEvent "Escape", "keydown"
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

context "PostFindMode",
  setup ->
    initializeModeState()

    testContent = "<input type='text' id='first'/>"
    document.getElementById("test-div").innerHTML = testContent
    document.getElementById("first").focus()
    @postFindMode = new PostFindMode

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "be a singleton", ->
    assert.isTrue @postFindMode.modeIsActive
    new PostFindMode
    assert.isFalse @postFindMode.modeIsActive

  should "suppress unmapped printable keys", ->
    sendKeyboardEvent "a"
    assert.equal null, commandCount

  should "be deactivated on click events", ->
    handlerStack.bubbleEvent "click", target: document.activeElement
    assert.isFalse @postFindMode.modeIsActive

  should "enter insert mode on immediate escape", ->
    sendKeyboardEvent "Escape", "keydown"
    assert.equal null, commandCount
    assert.isFalse @postFindMode.modeIsActive

  should "not enter insert mode on subsequent escapes", ->
    sendKeyboardEvent "a"
    sendKeyboardEvent "Escape", "keydown"
    assert.isTrue @postFindMode.modeIsActive

context "WaitForEnter",
  setup ->
    initializeModeState()
    @isSuccess = null
    @waitForEnter = new WaitForEnter (isSuccess) => @isSuccess = isSuccess

  should "exit with success on Enter", ->
    assert.isTrue @waitForEnter.modeIsActive
    assert.isFalse @isSuccess?
    sendKeyboardEvent "Enter", "keydown"
    assert.isFalse @waitForEnter.modeIsActive
    assert.isTrue @isSuccess? and @isSuccess == true

  should "exit without success on Escape", ->
    assert.isTrue @waitForEnter.modeIsActive
    assert.isFalse @isSuccess?
    sendKeyboardEvent "Escape", "keydown"
    assert.isFalse @waitForEnter.modeIsActive
    assert.isTrue @isSuccess? and @isSuccess == false

  should "not exit on other keyboard events", ->
    assert.isTrue @waitForEnter.modeIsActive
    assert.isFalse @isSuccess?
    sendKeyboardEvents "abc"
    assert.isTrue @waitForEnter.modeIsActive
    assert.isFalse @isSuccess?

context "GrabBackFocus",
  setup ->
    testContent = "<input type='text' value='some value' id='input'/>"
    document.getElementById("test-div").innerHTML = testContent
    stubSettings "grabBackFocus", true

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "blur an already focused input", ->
    document.getElementById("input").focus()
    assert.isTrue document.activeElement
    assert.isTrue DomUtils.isEditable document.activeElement
    initializeModeState()
    assert.isTrue document.activeElement
    assert.isFalse DomUtils.isEditable document.activeElement

  should "blur a newly focused input", ->
    initializeModeState()
    document.getElementById("input").focus()
    assert.isTrue document.activeElement
    assert.isFalse DomUtils.isEditable document.activeElement

  should "exit on a key event", ->
    initializeModeState()
    sendKeyboardEvent "a"
    document.getElementById("input").focus()
    assert.isTrue document.activeElement
    assert.isTrue DomUtils.isEditable document.activeElement

  should "exit on a mousedown event", ->
    initializeModeState()
    handlerStack.bubbleEvent "mousedown", target: document.body
    document.getElementById("input").focus()
    assert.isTrue document.activeElement
    assert.isTrue DomUtils.isEditable document.activeElement

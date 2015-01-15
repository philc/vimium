#
# Dispatching keyboard events via the DOM would require async tests,
# which tend to be more complicated. Here we create mock events and
# invoke the handlers directly.
#
mockKeyboardEvent = (keyChar) ->
  event = {}
  event.charCode = (if keyCodes[keyChar] isnt undefined then keyCodes[keyChar] else keyChar.charCodeAt(0))
  event.keyIdentifier = "U+00" + event.charCode.toString(16)
  event.keyCode = event.charCode
  event.stopImmediatePropagation = ->
  event.preventDefault = ->
  event

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
      testContent = "<a>test</a>" + "<a>tress</a>"
      document.getElementById("test-div").innerHTML = testContent
      stub settings.values, "filterLinkHints", isFilteredMode
      stub settings.values, "linkHintCharacters", "ab"
      stub settings.values, "linkHintNumbers", "0123456789"

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

  # See here about jQuery delegated events: https://api.jquery.com/on/#direct-and-delegated-events
  # TODO: Delegated events are handled asynchronously and cannot be tested now without extra hacks.
  #       Dependencies: philc/vimium/issues/1386     -- test framework, that supports async.
  #                     ariya/phantomjs/issues/11289 -- PhantomJS supports CustomEvent constructor since v2.0
  # context "Link hints for jQuery delegated events",
  #   setup ->
  #     stub settings.values, "filterLinkHints", isFilteredMode
  #     stub settings.values, "linkHintCharacters", "ab"
  #     stub settings.values, "linkHintNumbers", "0123456789"

  #     clickableSpan = "
  #       <div id='container'>
  #         <span class='clickable'>Click me</span>
  #         <span>Don't click me</span>
  #       </div>"
  #     document.getElementById("test-div").innerHTML = clickableSpan

  #     LinkHints.init()

  #   tearDown ->
  #     document.getElementById("test-div").innerHTML = ""

  #   should "create link hints for elements, being listened through document element", ->
  #     $(document).on 'click', '.clickable', ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 1, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "create link hints for elements, being listened through window element", ->
  #     $(window).on 'click', '.clickable', ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 1, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "create link hints for elements, being listened through parent DOM element", ->
  #     $("#container").on 'click', '.clickable', ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 1, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "create link hints for elements, attached with object syntax of `.on()`", ->
  #     $(document).on 'click': ( -> ), '.clickable'

  #     LinkHints.activateMode()
  #     assert.equal 1, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "create a link hint for parent if child has delegated event listener assigned", ->
  #     $("#container").on 'click', '.clickable', ( -> )
  #     $("#container").on 'click', ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 2, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "create a link hint for child if parent has normal event listener assigned", ->
  #     $("#container").on 'click', ( -> )
  #     $("#container").on 'click', '.clickable', ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 2, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "create one link hint if multiple delegate events are listened on a single element", ->
  #     $(document).on 'click', '.clickable', ( -> )
  #     $("#container").on 'click', '.clickable', ( -> )
  #     $("#container").on 'click', 'span.clickable', ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 1, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "create link hints for elements, being listened using deprecated `.live()` function", ->
  #     # `.live()` is implemented via `.on()` since jQuery 1.7, so it should work without modifications
  #     $('.clickable').live 'click', ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 1, getHintMarkers().length
  #     LinkHints.deactivateMode()

  #   should "work with any jQuery selector, even if it is not supported by `querySelectorAll`", ->
  #     document.getElementById("test-div").innerHTML = "<a href='#'>test</a>"
  #     $(document).on "click", "a[href=#]", ( -> )

  #     LinkHints.activateMode()
  #     assert.equal 1, getHintMarkers().length
  #     LinkHints.deactivateMode()


createGeneralHintTests false
createGeneralHintTests true

context "Alphabetical link hints",

  setup ->
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
    LinkHints.onKeyDownInMode hintMarkers, mockKeyboardEvent("A")
    assert.equal "none", hintMarkers[1].style.display
    assert.equal "", hintMarkers[0].style.display

context "Filtered link hints",

  setup ->
    stub settings.values, "filterLinkHints", true
    stub settings.values, "linkHintNumbers", "0123456789"

  context "Text hints",

    setup ->
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
      LinkHints.onKeyDownInMode hintMarkers, mockKeyboardEvent("T")
      LinkHints.onKeyDownInMode hintMarkers, mockKeyboardEvent("R")
      assert.equal "none", hintMarkers[0].style.display
      assert.equal "1", hintMarkers[1].hintString
      assert.equal "", hintMarkers[1].style.display
      LinkHints.onKeyDownInMode hintMarkers, mockKeyboardEvent("A")
      assert.equal "2", hintMarkers[3].hintString

  context "Image hints",

    setup ->
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
    testContent = "<input type='text' id='first'/><input style='display:none;' id='second'/>
      <input type='password' id='third' value='some value'/>"
    document.getElementById("test-div").innerHTML = testContent

  tearDown ->
    document.getElementById("test-div").innerHTML = ""

  should "focus the right element", ->
    focusInput 1
    assert.equal "first", document.activeElement.id
    # deactivate the tabbing mode and its overlays
    handlerStack.bubbleEvent 'keydown', mockKeyboardEvent("A")

    focusInput 100
    assert.equal "third", document.activeElement.id
    handlerStack.bubbleEvent 'keydown', mockKeyboardEvent("A")

# TODO: these find prev/next link tests could be refactored into unit tests which invoke a function which has
# a tighter contract than goNext(), since they test minor aspects of goNext()'s link matching behavior, and we
# don't need to construct external state many times over just to test that.
# i.e. these tests should look something like:
# assert.equal(findLink(html("<a href=...">))[0].href, "first")
# These could then move outside of the dom_tests file.
context "Find prev / next links",

  setup ->
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

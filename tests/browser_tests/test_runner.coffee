webdriver = require "selenium-webdriver"
fs = require "fs"
path = require "path"
test = require "selenium-webdriver/testing"
assert = require "assert"

{Builder, By, Condition, Key, until: Until} = webdriver

chromeOptions = ->
  try
    require "chromedriver"
  catch
    console.log "Could not find chromedriver package."
    return Promise.reject()

  chrome = require "selenium-webdriver/chrome"
  options = new chrome.Options()
  options.addArguments "load-extension=."
  Promise.resolve options

buildChrome = ->
  options = chromeOptions()
  options.then (options) ->
    new Builder()
      .forBrowser("chrome")
      .setChromeOptions(options)
      .build()

firefoxOptions = ->
  try
    require "geckodriver"
  catch
    console.log "Could not find geckodriver package."
    return Promise.reject()
  firefox = require "selenium-webdriver/firefox"
  profile = new firefox.Profile()
  profile.addExtension "."
  Promise.resolve new firefox.Options().setProfile profile

buildFirefox = ->
  options = firefoxOptions()
  options.then (options) ->
    new Builder()
      .forBrowser("firefox")
      .setFirefoxOptions(options)
      .build()

test.before (done) ->
  # Write to the test_harness_location file.
  fs.writeFile "tests/browser_tests/run_tests", "", {}, (err) ->
      if err?
        console.log "Error writing to run_tests file."
        throw err
      else
        done()

test.after (done) ->
  fs.unlink "tests/browser_tests/run_tests", (err) ->
    if err?
      console.log "Error deleting run_tests file."
      console.log err
    done()

findOpenTab = (driver, pageDescription, pageCondition) ->
  extensionHandle = driver.wait new Condition "for #{pageDescription} to open", ->
    driver.getAllWindowHandles().then (windowHandles) ->
      new Promise (resolve, reject) ->
        promise = windowHandles.reduce (accumulatedPromise, handle) ->
          accumulatedPromise
            .then -> driver.switchTo().window handle
            .then -> driver.getCurrentUrl()
            .then (url) ->
              if pageCondition url
                resolve handle
                Promise.reject()
        , Promise.resolve()
        promise.then (-> resolve false), -> resolve false

  Promise.all [extensionHandle, extensionHandle.then -> driver.getCurrentUrl()]

getLinkHints = (driver) -> driver.findElements By.className "vimiumHintMarker"

abortTests = -> false
it = (testName, testFunction) ->
  test.it testName, ->
    @skip() if abortTests()
    testFunction.apply this, arguments

driver = undefined
testbedHandle = undefined
harnessHandle = harnessUrl = undefined

runTests = (driverName, driverBuilder) ->
  new Promise (resolve) ->
    test.describe "#{driverName} tests", ->
      test.before ->
        @timeout 20000
        driverBuilder().then (newDriver) -> driver = newDriver
      test.after -> driver.quit()

      it "should open the test harness page", ->
        abortTests = -> true # Don't run any later tests if the test harness doesn't open.
        findOpenTab driver, "test harness", (url) -> url.match /^(chrome|moz)-extension:\/\//
          .then (results) ->
            abortTests = -> false
            [harnessHandle, harnessUrl] = results

      it "should have the chrome API in the test harness page", ->
        triesLeft = 3
        findChrome = ->
          driver.executeScript -> chrome
          .catch (err) ->
            if triesLeft > 0
              # Firefox doesn't inject the API if we open the tab too early. Try loading again a few times.
              triesLeft--
              driver.executeScript -> location.reload()
            else
              throw err

        findChrome()

      it "should open the testbed", ->
        abortTests = -> true # Don't run any later tests if the testbed doesn't open.
        findOpenTab driver, "start page", (url) -> not url.match /^(chrome|moz)-extension:\/\//
        driver.get "file://" + path.resolve "./tests/browser_tests/testbed.html"
          .then -> driver.getWindowHandle()
          .then (handle) ->
            abortTests = -> false
            testbedHandle = handle

      test.describe "Link hints: alphabet hints", ->
        linkHintTests false
      test.describe "Link hints: filter hints", ->
        linkHintTests true

changeSetting = (key, value) ->
  driver.switchTo().window harnessHandle
  driver.executeAsyncScript (key, value, callback) ->
    chrome.runtime.getBackgroundPage (bgWindow) ->
      value ?= undefined # Selenium converts undefined to null; convert it back.
      bgWindow.Settings.testCallback = -> chrome.storage.sync.get key, callback
      bgWindow.Settings.set key, value
  , key, value
  .then (newValues) ->
    assert.equal newValues[key], JSON.stringify(value)
    newValues

clearSetting = (key) ->
  driver.switchTo().window harnessHandle
  driver.executeAsyncScript (key, callback) ->
    chrome.runtime.getBackgroundPage (bgWindow) ->
      bgWindow.Settings.testCallback = callback
      bgWindow.Settings.clear key
  , key

setTestContent = (testContent) ->
  driver.switchTo().window testbedHandle
  driver.executeScript (testContent) ->
    document.getElementById("test-div").innerHTML = testContent
  , testContent

addClickListener = ->
  driver.executeScript ->
    window.addEventListener "click", window.clickListener = (event) ->
      count = parseInt(event.target.getAttribute "clicked") || 0
      event.target.setAttribute "clicked", count + 1
    , true

linkHintTests = (filterLinkHints) ->
  test.describe "", ->
    settings = {filterLinkHints, "linkHintCharacters": "ab", "linkHintNumbers": "12"}
    test.before ->
      Promise.all Object.keys(settings).map (key) ->
        changeSetting key, settings[key], true
      .then ->setTestContent "<a>test</a>" + "<a>tress</a>"

    test.afterEach ->
      driver.executeScript -> window.removeEventListener "click", window.clickListener, true

    test.after -> Promise.all Object.keys(settings).map clearSetting

    it "should create hints when activated, discard them when deactivated", ->
      markerContainer = undefined
      driver.findElement(By.css "body").sendKeys "f"
      driver.wait Until.elementLocated By.id "vimiumHintMarkerContainer"
      .then (res) -> markerContainer = res
      .then -> driver.findElement(By.css "body").sendKeys Key.ESCAPE
      .then -> driver.wait Until.stalenessOf markerContainer

    assertStartPosition = (element1, element2) ->
      Promise.all [element1.getLocation(), element2.getLocation()]
        .then ([el1, el2]) ->
          assert.equal el1.x, el2.x
          assert.equal el1.y, el2.y

    testPosition = (position) ->
      it "position items correctly in body {position: #{position}}", ->
        driver.executeScript ((position) -> document.body.style.position = position), position

        driver.findElement(By.css "body").sendKeys "f"
        links = undefined
        hints = undefined
        driver.findElements By.css "a"
          .then (res) ->
            links = res
            assert.equal links.length, 2, "there should be 2 links, not #{links.length}"
        driver.wait Until.elementsLocated By.className "vimiumHintMarker"
          .then (res) ->
            hints = res
            assert.equal hints.length, 2, "there should be 2 hints, not #{hints.length}"
          .then -> assertStartPosition links[0], hints[0]
          .then -> assertStartPosition links[1], hints[1]
          .then -> driver.findElement(By.css "body").sendKeys Key.ESCAPE
          .then -> driver.executeScript -> delete document.body.style.position

    testPosition "static"
    testPosition "relative"

    it "should handle false positives", ->
      setTestContent '<span class="buttonWrapper">false positive<a>clickable</a></span>' + '<span class="buttonWrapper">clickable</span>'
      addClickListener()
      Promise.all [0, 1].map (i) ->
        driver.findElement(By.css "body").sendKeys "f"
        driver.wait Until.elementsLocated By.className "vimiumHintMarker"
        .then (hints) ->
          assert.equal hints.length, 2, "There should be 2 hints, not #{hints.length}"
          assert hints[i], "Can't find link #{i}."
          hints[i].getText()
        .then (text) -> driver.findElement(By.css "body").sendKeys text
        .then -> driver.findElements By.id "vimiumHintMarkerContainer"
        .then (markerContainers) ->
          if markerContainers.length > 0 # Hints haven't disappeared; need to press enter.
            driver.findElement(By.css "body").sendKeys Key.ENTER

      .then ->
        driver.findElement By.id "test-div"
        .findElements By.css "*"
        .then (children) ->
          Promise.all children.map (child) ->
            Promise.all [child.getText(), child.getAttribute "clicked"]
            .then ([text, clicked]) ->
              if text == "clickable"
                assert.equal clicked, 1
              else
                assert.equal clicked, null

    ["click:namespace.actionName", "namespace.actionName"].map (text) ->
      it "should match jsaction elements with jsaction=#{text}", ->
        addClickListener()
        setTestContent '<p id="test-paragraph" jsaction="' + text + '">clickable</p>'

        Promise.all [0].map (i) ->
          driver.findElement(By.css "body").sendKeys "f"
          driver.wait Until.elementsLocated By.className "vimiumHintMarker"
          .then (hints) ->
            assert hints.length, 1, "there should be 1 hint, not #{hints.length}."
            assert hints[i], "Can't find link #{i}."
            hints[i].getText()
          .then (text) -> driver.findElement(By.css "body").sendKeys text
          .then -> driver.findElements By.id "vimiumHintMarkerContainer"
          .then (markerContainers) ->
            if markerContainers.length > 0 # Hints haven't disappeared; need to press enter.
              driver.findElement(By.css "body").sendKeys Key.ENTER

        .then ->
          driver.findElement By.id "test-div"
          .findElements By.css "*"
          .then (children) ->
            Promise.all children.map (child) ->
              Promise.all [child.getText(), child.getAttribute "clicked"]
              .then ([text, clicked]) ->
                if text == "clickable"
                  assert.equal clicked, 1
                else
                  assert.equal clicked, null

    ["mousedown:namespace.actionName", "click:namespace._", "none", "namespace:_"].map (text) ->
      it "should not match inactive jsaction elements with jsaction=#{text}", ->
        addClickListener()
        setTestContent '<a>clickable</a><p id="test-paragraph" jsaction="' + text + '">unclickable</p>'
        Promise.all [0].map (i) ->
          driver.findElement(By.css "body").sendKeys "f"
          driver.wait Until.elementsLocated By.className "vimiumHintMarker"
          .then (hints) ->
            assert hints.length, 1, "there should be 1 hint, not #{hints.length}."
            assert hints[i], "Can't find link #{i}."
            hints[i].getText()
          .then (text) -> driver.findElement(By.css "body").sendKeys text
          .then -> driver.findElements By.id "vimiumHintMarkerContainer"
          .then (markerContainers) ->
            if markerContainers.length > 0 # Hints haven't disappeared; need to press enter.
              driver.findElement(By.css "body").sendKeys Key.ENTER

        .then ->
          driver.findElement By.id "test-div"
          .findElements By.css "*"
          .then (children) ->
            Promise.all children.map (child) ->
              Promise.all [child.getText(), child.getAttribute "clicked"]
              .then ([text, clicked]) ->
                if text == "clickable"
                  assert.equal clicked, 1
                else
                  assert.equal clicked, null

    test.describe "should select input elements correctly", ->
      inputTypes = ["button", "color", "checkbox", "date", "datetime", "datetime-local", "email", "file",
      "image", "month", "number", "password", "radio", "range", "reset", "search", "submit", "tel", "text",
      "time", "url", "week"]

      testSpecs = inputTypes.map (type) -> {type, name: "input type=#{type}", testContent: "<input type='#{type}' />"}
      testSpecs.push name: "select", testContent: "<select></select>"

      testSpecs.map ({type, name, testContent}) ->
        it name, ->
          setTestContent testContent
          addClickListener()
          driver.executeScript (type) ->
            for input in document.getElementById("test-div").children
              input.addEventListener "focus", (event) ->
                count = parseInt(event.target.getAttribute "focused") || 0
                event.target.setAttribute "focused", count + 1
              , true
              if type == "file"
                # We have no way of shutting the dialog that <input type=file> opens, so we avoid opening it.
                input.addEventListener "click", (event) ->
                  event.preventDefault()
                , true
          , type

          Promise.all [0].map (i) ->
            driver.findElement(By.css "body").sendKeys "f"
            driver.wait Until.elementsLocated By.className "vimiumHintMarker"
            .then (hints) ->
              assert hints.length, 1, "there should be 1 hint, not #{hints.length}."
              assert hints[i], "Can't find link #{i}."
              hints[i].getText()
            .then (text) -> driver.findElement(By.css "body").sendKeys text
            .then -> driver.findElements By.id "vimiumHintMarkerContainer"
            .then (markerContainers) ->
              if markerContainers.length > 0 # Hints haven't disappeared; need to press enter.
                driver.findElement(By.css "body").sendKeys Key.ENTER

          .then ->
            driver.findElement By.id "test-div"
            .findElements By.css "*"
            .then (children) ->
              Promise.all children.map (child) ->
                Promise.all [child.getAttribute("clicked"), child.getAttribute "focused"]
                .then ([clicked, focused]) ->
                  assert clicked || focused

runTests "Chrome", buildChrome
runTests "Firefox", buildFirefox

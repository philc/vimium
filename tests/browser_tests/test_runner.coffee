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
  fs.writeFile "tests/browser_tests/test_harness_location",
    "tests/browser_tests/test_harness.html?test_base_location=file:///#{path.resolve "tests/browser_tests"}",
    {}, (err) ->
      if err?
        console.log "Error writing to test_harness_location file."
        throw err
      else
        done()

test.after (done) ->
  fs.unlink "tests/browser_tests/test_harness_location", (err) ->
    if err?
      console.log "Error deleting test_harness_location file."
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

runTests = (driverName, driverBuilder) ->
  new Promise (resolve) ->
    test.describe "#{driverName} tests", ->
      driver = undefined
      harnessHandle = harnessUrl = undefined

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

      test.describe "Link hints", ->
        abortLinkHintTests = false
        oldAbortTests = abortTests
        abortTests = -> abortLinkHintTests or oldAbortTests()
        it "should open the link hints test page", ->
          abortLinkHintTests = true
          findOpenTab driver, "link hints testbed", (url) -> url.match /\/link_hints.html$/
            .then -> abortLinkHintTests = false

        it "should create hints when activated", ->
          driver.findElement(By.css "body").sendKeys "f"
          driver.findElements By.id "vimiumHintMarkerContainer"
            .then (markerContainers) -> assert.equal markerContainers.length, 1

        it "should discard hints when deactivated", ->
          driver.findElement(By.css "body").sendKeys Key.ESCAPE
          driver.findElements By.id "vimiumHintMarkerContainer"
            .then (markerContainers) -> assert.equal markerContainers.length, 0

        test.describe "position items correctly", ->
          assertStartPosition = (element1, element2) ->
            Promise.all [element1.getLocation(), element2.getLocation()]
              .then ([el1, el2]) ->
                assert.equal el1.x, el2.x
                assert.equal el1.y, el2.y

          test.after -> driver.executeScript -> delete document.body.style.position

          testPosition = (position) ->
            it "body {position: #{position}}", ->
              driver.executeScript ((position) -> document.body.style.position = position), position

              driver.findElement(By.css "body").sendKeys "f"
              links = undefined
              hints = undefined
              driver.findElements By.css "a"
                .then (res) ->
                  links = res
                  assert links.length >= 2, "too few links."
              driver.wait Until.elementLocated By.className "vimiumHintMarker"
              driver.findElements By.className "vimiumHintMarker"
                .then (res) ->
                  hints = res
                  assert hints.length >= 2, "too few link hints."
                .then -> assertStartPosition links[0], hints[0]
                .then -> assertStartPosition links[1], hints[1]
                .then -> driver.findElement(By.css "body").sendKeys Key.ESCAPE

          testPosition "static"
          testPosition "relative"

        abortTests = oldAbortTests


runTests "Chrome", buildChrome
# Firefox tests disabled pending a method to open the testbeds.
#runTests "Firefox", buildFirefox

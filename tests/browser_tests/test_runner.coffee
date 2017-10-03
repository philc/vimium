webdriver = require "selenium-webdriver"
fs = require "fs"

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
    new webdriver.Builder()
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
    new webdriver.Builder()
      .forBrowser("firefox")
      .setFirefoxOptions(options)
      .build()

exports.run = ->
  new Promise (resolve) ->
    # Write to the test_harness_location file.
    fs.writeFile "tests/browser_tests/test_harness_location", "tests/browser_tests/test_harness.html", {},
    (err) -> if err?
      console.log "Error writing to test_harness_location file."
      throw err
    else resolve()
  .then ->
    console.log "Running Chrome tests..."
    buildChrome()
  .then runTests, (failure) ->
    console.log failure if failure?
    console.log "Chrome tests aborted."
  .then ->
    console.log "Running Firefox tests..."
    buildFirefox()
  .then runTests, (failure) ->
    console.log failure if failure?
    console.log "Firefox tests aborted."
  .then ->
    new Promise (resolve, reject) ->
      fs.unlink "tests/browser_tests/test_harness_location", (err) ->
        if err?
          console.log "Error deleting test_harness_location file."
          console.log err
        resolve()


runTests = (driver) ->
  extensionHandle = driver.wait new webdriver.Condition "for extension tab to open", ->
    driver.getAllWindowHandles().then (windowHandles) ->
      new Promise (resolve, reject) ->
        promise = windowHandles.reduce (accumulatedPromise, handle) ->
          accumulatedPromise
            .then -> driver.switchTo().window handle
            .then -> driver.getCurrentUrl()
            .then (url) ->
              if url.match /^(chrome|moz)-extension:\/\//
                resolve handle
                Promise.reject()
        , Promise.resolve()
        promise.then (-> resolve false), -> resolve false

  extensionHandle.then ->
    driver.getCurrentUrl().then console.log
    driver.quit()
  .catch -> console.log "Could not find the test harness page."

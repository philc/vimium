webdriver = require "selenium-webdriver"

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
  console.log "Running Chrome tests..."
  buildChrome().then (chromeDriver) ->
    chromeDriver.quit()
  , (failure) ->
    console.log failure if failure?
    console.log "Chrome tests aborted."
  .then ->
    console.log "Running Firefox tests..."
    buildFirefox().then (firefoxDriver) ->
      firefoxDriver.quit()
    , (failure) ->
      console.log failure if failure?
      console.log "Firefox tests aborted."

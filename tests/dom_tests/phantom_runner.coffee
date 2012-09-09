system = require 'system'
fs = require 'fs'
page = require('webpage').create()

page.settings.userAgent = 'phantom'

# ensure that the elements we test the link hints on are actually visible
page.viewportSize =
  width: 900
  height: 600

page.onConsoleMessage = (msg) ->
  console.log msg

dirname = do ->
  pathParts = system.args[0].split(fs.separator)
  pathParts[pathParts.length - 1] = ''
  pathParts.join(fs.separator)

page.open dirname + 'dom_tests.html', (status) ->
  if status != 'success'
    console.log 'Unable to load tests.'
    phantom.exit 1

  testsFailed = page.evaluate ->
    Tests.run()
    return Tests.testsFailed

  if system.args[1] == '--coverage'
    data = page.evaluate -> JSON.stringify _$jscoverage
    fs.write dirname + 'dom_tests_coverage.json', data, 'w'

  if testsFailed > 0
    phantom.exit 1
  else
    phantom.exit 0

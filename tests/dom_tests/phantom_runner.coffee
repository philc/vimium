system = require 'system'
fs = require 'fs'
path = require 'path'
page = require('webpage').create()

page.settings.userAgent = 'phantom'

# ensure that the elements we test the link hints on are actually visible
page.viewportSize =
  width: 900
  height: 600

page.onConsoleMessage = (msg) ->
  console.log msg

page.onError = (msg, trace) ->
  console.log(msg);
  trace.forEach (item) ->
    console.log('  ', item.file, ':', item.line)

page.onResourceError = (resourceError) ->
  console.log(resourceError.errorString)

testfile = path.join(path.dirname(system.args[0]), 'dom_tests.html')
page.open testfile, (status) ->
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

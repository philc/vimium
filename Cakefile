fs = require "fs"
{spawn, exec} = require "child_process"

task "build", "compile all coffeescript files to javascript", ->
  coffee = spawn "coffee", ["tests", "background_scripts", "content_scripts", "lib"]
  coffee.stdout.on "data", (data) -> console.log data.toString().trim()

task "autobuild", "continually rebuild coffeescript files using coffee --watch", ->
  coffee = spawn "coffee", ["-cw", "tests", "background_scripts", "content_scripts", "lib"]
  coffee.stdout.on "data", (data) -> console.log data.toString().trim()

task "test", "run all unit tests", ->
  # Run running the command `node tests/*_test.js`.
  test_files = fs.readdirSync("tests/").filter((filename) -> filename.indexOf("_test.js") > 0)
  test_files = test_files.map((filename) -> "tests/" + filename)
  test_files.forEach (file) -> require "./" + file
  Tests.run()

fs = require "fs"
{spawn, exec} = require "child_process"

task "autobuild", "continually rebuild coffeescript files using coffee --watch", ->
  coffee = spawn "coffee", ["-cw", "tests", "background_scripts"]
  coffee.stdout.on "data", (data) -> console.log data.toString().trim()

task "test", "run all unit tests", ->
  # Run running the command `node tests/*_test.js`.
  test_files = fs.readdirSync("tests/").filter((filename) -> filename.indexOf("_test.js") > 0)
  test_files = test_files.map((filename) -> "tests/" + filename)
  node = spawn "node", test_files
  node.stdout.on "data", (data) -> console.log data.toString().trim()
  node.stderr.on "data", (data) -> console.log data.toString().trim()

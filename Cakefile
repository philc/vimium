fs = require "fs"
{spawn, exec} = require "child_process"

src_directories = ["tests", "background_scripts", "content_scripts", "lib"]

task "build", "compile all coffeescript files to javascript", ->
  coffee = spawn "coffee", src_directories
  coffee.stdout.on "data", (data) -> console.log data.toString().trim()

task "clean", "removes any js files which were compiled from coffeescript", ->
  src_directories.forEach (directory) ->
    files = fs.readdirSync(directory).filter((filename) -> filename.indexOf(".js") > 0)
    files = files.map((filename) -> "#{directory}/#{filename}")
    files.forEach((file) -> fs.unlinkSync file if fs.statSync(file).isFile())

task "autobuild", "continually rebuild coffeescript files using coffee --watch", ->
  coffee = spawn "coffee", ["-cw"].concat(src_directories)
  coffee.stdout.on "data", (data) -> console.log data.toString().trim()

task "test", "run all unit tests", ->
  test_files = fs.readdirSync("tests/").filter((filename) -> filename.indexOf("_test.js") > 0)
  test_files = test_files.map((filename) -> "tests/" + filename)
  test_files.forEach (file) -> require "./" + file
  Tests.run()

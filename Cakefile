fs = require "fs"
path = require "path"
{spawn, exec} = require "child_process"

spawn_with_opts = (proc_name, opts) ->
  opt_array = []
  for key, value of opts
    opt_array.push "--#{key}=#{value}"
  spawn proc_name, opt_array

src_directories = ["tests", "background_scripts", "content_scripts", "lib"]

task "build", "compile all coffeescript files to javascript", ->
  coffee = spawn "coffee", ["-c"].concat(src_directories)
  coffee.stdout.on "data", (data) -> console.log data.toString().trim()

task "clean", "removes any js files which were compiled from coffeescript", ->
  src_directories.forEach (directory) ->
    fs.readdirSync(directory).forEach (filename) ->
      return unless (path.extname filename) == ".js"
      filepath = path.join directory, filename
      return unless (fs.statSync filepath).isFile()

      # Check if there exists a corresponding .coffee file
      try
        coffeeFile = fs.statSync path.join directory, "#{path.basename filepath, ".js"}.coffee"
      catch _
        return

      fs.unlinkSync filepath if coffeeFile.isFile()

task "autobuild", "continually rebuild coffeescript files using coffee --watch", ->
  coffee = spawn "coffee", ["-cw"].concat(src_directories)
  coffee.stdout.on "data", (data) -> console.log data.toString().trim()

task "package", "build .crx file", ->
  invoke "build"

  # ugly hack to modify our manifest file on-the-fly
  orig_manifest_text = fs.readFileSync "manifest.json"
  manifest = JSON.parse orig_manifest_text
  manifest.update_url = "http://philc.github.com/vimium/updates.xml"
  fs.writeFileSync "manifest.json", JSON.stringify manifest

  crxmake = spawn_with_opts "crxmake"
    "pack-extension": "."
    "pack-extension-key": "vimium.pem"
    "extension-output": "vimium-latest.crx"
    "ignore-file": "(^\\.|\\.(coffee|crx|pem|un~)$)"
    "ignore-dir": "^(\\.|test)"

  crxmake.stdout.on "data", (data) -> console.log data.toString().trim()
  crxmake.on "exit", -> fs.writeFileSync "manifest.json", orig_manifest_text

task "test", "run all unit tests", ->
  test_files = fs.readdirSync("tests/").filter((filename) -> filename.indexOf("_test.js") > 0)
  test_files = test_files.map((filename) -> "tests/" + filename)
  test_files.forEach (file) -> require "./" + file
  Tests.run()
  if Tests.testsFailed > 0
    process.exit 1

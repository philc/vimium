fs = require "fs"
path = require "path"
child_process = require "child_process"

spawn = (procName, optArray, silent=false) ->
  proc = child_process.spawn procName, optArray
  unless silent
    proc.stdout.on 'data', (data) -> process.stdout.write data
    proc.stderr.on 'data', (data) -> process.stderr.write data
  proc

optArrayFromDict = (opts) -> "--#{key}=#{value}" for key, value of opts

task "build", "compile all coffeescript files to javascript", ->
  coffee = spawn "coffee", ["-c", __dirname]

task "clean", "removes any js files which were compiled from coffeescript", ->
  visit = (directory) ->
    fs.readdirSync(directory).forEach (filename) ->
      filepath = path.join directory, filename
      if (fs.statSync filepath).isDirectory()
        return visit filepath

      return unless (path.extname filename) == ".js" and (fs.statSync filepath).isFile()

      # Check if there exists a corresponding .coffee file
      try
        coffeeFile = fs.statSync path.join directory, "#{path.basename filepath, ".js"}.coffee"
      catch _
        return

      fs.unlinkSync filepath if coffeeFile.isFile()

  visit __dirname

task "autobuild", "continually rebuild coffeescript files using coffee --watch", ->
  coffee = spawn "coffee", ["-cw", __dirname]

task "package", "build .crx file", ->
  invoke "build"

  # ugly hack to modify our manifest file on-the-fly
  origManifestText = fs.readFileSync "manifest.json"
  manifest = JSON.parse origManifestText
  manifest.update_url = "http://philc.github.com/vimium/updates.xml"
  fs.writeFileSync "manifest.json", JSON.stringify manifest

  crxmake = spawn "crxmake", optArrayFromDict
    "pack-extension": "."
    "pack-extension-key": "vimium.pem"
    "extension-output": "vimium-latest.crx"
    "ignore-file": "(^\\.|\\.(coffee|crx|pem|un~)$)"
    "ignore-dir": "^(\\.|test)"

  crxmake.on "exit", -> fs.writeFileSync "manifest.json", origManifestText

task "test", "run all tests", ->
  console.log "Running unit tests..."
  basedir = "tests/unit_tests/"
  test_files = fs.readdirSync(basedir).filter((filename) -> filename.indexOf("_test.js") > 0)
  test_files = test_files.map((filename) -> basedir + filename)
  test_files.forEach (file) -> require "./" + file
  Tests.run()
  returnCode = if Tests.testsFailed > 0 then 1 else 0

  console.log "Running DOM tests..."
  phantom = spawn "phantomjs", ["./tests/dom_tests/phantom_runner.js"]
  phantom.on 'exit', (code) ->
    returnCode += code
    process.exit returnCode

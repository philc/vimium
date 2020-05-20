#!/usr/bin/env node
// Usage: ./make.js command. Use -h for help.
// This is a set of tasks for building and testing Vimium in development.

fs = require("fs");
child_process = require("child_process");

// Spawns a new process and returns it.
function spawn(procName, optArray, silent = false, sync = false) {
  if (process.platform == "win32") {
    // if win32, prefix arguments with "/c {original command}"
    // e.g. "mkdir c:\git\vimium" becomes "cmd.exe /c mkdir c:\git\vimium"
    optArray.unshift("/c", procName)
    procName = "cmd.exe"
  }
  proc = null
  if (sync) {
    proc = child_process.spawnSync(procName, optArray, {
      stdio: [undefined, process.stdout, process.stderr]
    });
  } else {
    proc = child_process.spawn(procName, optArray)
    if (!silent) {
      proc.stdout.on('data', (data) => process.stdout.write(data));
      proc.stderr.on('data', (data) => process.stderr.write(data));
    }
  }
  return proc;
}

// Builds a zip file for submission to the Chrome store. The output is in dist/.
function buildStorePackage() {
  const vimiumVersion = JSON.parse(fs.readFileSync("manifest.json").toString())["version"]

  spawn("rm", ["-rf", "dist/vimium"], false, true);
  spawn("mkdir", ["-p", "dist/vimium"], false, true);
  spawn("mkdir", ["-p", "dist/chrome-store"], false, true);
  spawn("mkdir", ["-p", "dist/chrome-canary"], false, true);
  spawn("mkdir", ["-p", "dist/firefox"], false, true);

  const blacklist = [".*", "*.md", "test_harnesses", "tests", "dist", "CREDITS", "node_modules",
                     "MIT-LICENSE.txt", "package-lock.json", "make.js"];
  const rsyncOptions = [].concat.apply(
    ["-r", ".", "dist/vimium"],
    blacklist.map((item) => ["--exclude", item]));

  spawn("rsync", rsyncOptions, false, true);

  const manifestContents = fs.readFileSync("dist/vimium/manifest.json").toString();
  const chromeManifest = JSON.parse(manifestContents);
  const firefoxManifest = JSON.parse(manifestContents);
  const writeDistManifest = (manifestObject) => {
    fs.writeFileSync("dist/vimium/manifest.json", JSON.stringify(manifestObject, null, 2));
  };

  // cd into "dist/vimium" before building the zip, so that the files in the zip don't each have the
  // path prefix "dist/vimium".
  // --filesync ensures that files in the archive which are no longer on disk are deleted. It's equivalent to
  // removing the zip file before the build.
  const zipCommand = "cd dist/vimium && zip -r --filesync ";

  // Chrome considers this key invalid in manifest.json, so we add it during the build phase.
  firefoxManifest["browser_specific_settings"] = {
    gecko: {
      "strict_min_version": "62.0"
    }
  };

  writeDistManifest(firefoxManifest);
  spawn("bash", ["-c", zipCommand + `../firefox/vimium-firefox-${vimiumVersion}.zip .`], false, true);

  // Build the Chrome Store package. Chrome does not require the clipboardWrite permission.
  chromeManifest.permissions = chromeManifest.permissions.filter((p) => p != "clipboardWrite");
  writeDistManifest(chromeManifest);
  spawn("bash", ["-c", zipCommand + `../chrome-store/vimium-chrome-store-${vimiumVersion}.zip .`], false, true);

  // Build the Chrome Store dev package.
  chromeManifest.name = "Vimium Canary";
  chromeManifest.description = "This is the development branch of Vimium (it is beta software).";
  writeDistManifest(chromeManifest);
  spawn("bash", ["-c", zipCommand + `../chrome-canary/vimium-canary-${vimiumVersion}.zip .`], false, true);
}


// Returns how many tests failed.
function runUnitTests() {
  console.log("Running unit tests...")
  projectDir = "."
  basedir = __dirname + "/tests/unit_tests/";
  test_files = fs.readdirSync(basedir).filter((filename) => filename.indexOf("_test.js") > 0)
  test_files = test_files.map((filename) => basedir + filename)
  test_files.forEach((file) => {
    path = (file[0] == '/' ? '' : './') + file;
    require(path);
  });
  return Tests.run();
}

// Returns how many tests fail.
function runDomTests() {
  const puppeteer = require("puppeteer");

  const testFile = __dirname + "/tests/dom_tests/dom_tests.html";

  (async () => {
    const browser = await puppeteer.launch({
      // NOTE(philc): "Disabling web security" is required for vomnibar_test.js, because we have a file://
      // page accessing an iframe, and Chrome prevents this because it's a cross-origin request.
      args: ['--disable-web-security']
    });
    const page = await browser.newPage();
    page.on("console", msg => console.log(msg.text()));
    page.on("error", (err) => console.log(err));
    page.on("pageerror", (err) => console.log(err));
    await page.goto("file://" + testFile);
    const testsFailed = await page.evaluate(() => {
      Tests.run();
      return Tests.testsFailed;
    });
    await browser.close();
    return testsFailed;
  })();
}

// Prints the list of valid commands.
function printHelpString() {
  console.log("Usage: ./make.js command\n\nValid commands:");
  const keys = Object.keys(commands).sort();
  for (let k of keys)
    console.log(k, ":", commands[k].help);
}

const commands = []
// Defines a new command.
function command(name, helpString, fn) {
  commands[name] = { help: helpString, fn: fn };
}

command(
  "test",
  "Run all tests",
  () => {
    let failed = runUnitTests();
    failed += runDomTests();
    if (failed > 0)
      Process.exit(1);
  });

command(
  "test-unit",
  "Run unit tests",
  () => {
    const failed = runUnitTests() > 0;
    if (failed > 0)
      Process.exit(1);
  });

command(
  "test-dom",
  "Run DOM tests",
  () => {
    const failed = runDomTests();
    if (failed > 0)
      Process.exit(1);
  });

command(
  "package",
  "Builds a zip file for submission to the Chrome store. The output is in dist/",
  buildStorePackage);

if (process.argv.includes("-h") || process.argv.includes("--help") || process.argv.length == 2) {
  printHelpString();
  return;
}

commandArg = process.argv[2]

if (commands[commandArg]) {
  commands[commandArg].fn();
} else {
  printHelpString();
  process.exit(1);
}

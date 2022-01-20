#!/usr/bin/env node
// Usage: ./make.js command. Use -h for help.
// This is a set of tasks for building and testing Vimium in development.

fs = require("fs");
child_process = require("child_process");

// Spawns a new process and returns it.
function spawn(procName, optArray, silent = false, sync = true) {
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

// Builds a zip file for submission to the Chrome and Firefox stores. The output is in dist/.
function buildStorePackage() {
  const excludeList = [
    "*.md",
    ".*",
    "CREDITS",
    "MIT-LICENSE.txt",
    "dist",
    "make.js",
    "node_modules",
    "package-lock.json",
    "test_harnesses",
    "tests",
  ];
  const manifestContents = require("./manifest.json");
  const rsyncOptions = ["-r", ".", "dist/vimium"].concat(
    ...excludeList.map((item) => ["--exclude", item])
  );
  const vimiumVersion = require("./manifest.json").version;
  const writeDistManifest = (manifestObject) => {
    fs.writeFileSync("dist/vimium/manifest.json", JSON.stringify(manifestObject, null, 2));
  };
  // cd into "dist/vimium" before building the zip, so that the files in the zip don't each have the
  // path prefix "dist/vimium".
  // --filesync ensures that files in the archive which are no longer on disk are deleted. It's equivalent to
  // removing the zip file before the build.
  const zipCommand = "cd dist/vimium && zip -r --filesync ";

  spawn("rm", ["-rf", "dist/vimium"]);
  spawn("mkdir", ["--parents", "dist/vimium", "dist/chrome-canary", "dist/chrome-store", "dist/firefox"]);
  spawn("rsync", rsyncOptions);

  writeDistManifest(Object.assign({}, manifestContents, {
    // Chrome considers this key invalid in manifest.json, so we add it during the build phase.
    browser_specific_settings: {
      gecko: {
        strict_min_version: "62.0"
      },
    },
  }));
  spawn("bash", ["-c", `${zipCommand} ../firefox/vimium-firefox-${vimiumVersion}.zip .`]);

  // Build the Chrome Store package. Chrome does not require the clipboardWrite permission.
  const permissions = manifestContents.permissions.filter((p) => p != "clipboardWrite");
  writeDistManifest(Object.assign({}, manifestContents, {
    permissions,
  }));
  spawn("bash", ["-c", `${zipCommand} ../chrome-store/vimium-chrome-store-${vimiumVersion}.zip .`]);

  // Build the Chrome Store dev package.
  writeDistManifest(Object.assign({}, manifestContents, {
    name: "Vimium Canary",
    description: "This is the development branch of Vimium (it is beta software).",
    permissions,
  }));
  spawn("bash", ["-c", `${zipCommand} ../chrome-canary/vimium-canary-${vimiumVersion}.zip .`]);
}


// Returns how many tests failed.
function runUnitTests() {
  console.log("Running unit tests...")
  const basedir = __dirname + "/tests/unit_tests/";
  fs.readdirSync(basedir).forEach((filename) => {
    if (filename.endsWith("_test.js")) {
      require(basedir + filename);
    }
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
    const failed = runUnitTests() + runDomTests();
    if (failed > 0)
      Process.exit(failed);
  });

command(
  "test-unit",
  "Run unit tests",
  () => {
    const failed = runUnitTests();
    if (failed > 0)
      Process.exit(failed);
  });

command(
  "test-dom",
  "Run DOM tests",
  () => {
    const failed = runDomTests();
    if (failed > 0)
      Process.exit(failed);
  });

command(
  "package",
  "Builds a zip file for submission to the Chrome and Firefox stores. The output is in dist/",
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

#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env --allow-net --allow-run --unstable
// --unstable is required for Puppeteer.
// Usage: ./make.js command. Use -l to list commands.
// This is a set of tasks for building and testing Vimium in development.
import * as fs from "https://deno.land/std/fs/mod.ts";
import * as fsCopy from "https://deno.land/std@0.122.0/fs/copy.ts";
import * as path from "https://deno.land/std@0.136.0/path/mod.ts";
import { desc, run, task } from "https://deno.land/x/drake@v1.5.1/mod.ts";
import puppeteer from "https://deno.land/x/puppeteer@9.0.2/mod.ts";
import * as shoulda from "./tests/vendor/shoulda.js";

const projectPath = new URL(".", import.meta.url).pathname;

async function shell(procName, argsArray = []) {
  // NOTE(philc): Does drake's `sh` function work on Windows? If so, that can replace this function.
  if (Deno.build.os == "windows") {
    // if win32, prefix arguments with "/c {original command}"
    // e.g. "mkdir c:\git\vimium" becomes "cmd.exe /c mkdir c:\git\vimium"
    optArray.unshift("/c", procName)
    procName = "cmd.exe"
  }
  const p = Deno.run({ cmd: [procName].concat(argsArray) });
  const status = await p.status();
  if (!status.success)
    throw new Error(`${procName} ${argsArray} exited with status ${status.code}`);
}

// Builds a zip file for submission to the Chrome and Firefox stores. The output is in dist/.
async function buildStorePackage() {
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
  const fileContents = await Deno.readTextFile("./manifest.json");
  const manifestContents = JSON.parse(fileContents);
  const rsyncOptions = ["-r", ".", "dist/vimium"].concat(
    ...excludeList.map((item) => ["--exclude", item])
  );
  const vimiumVersion = manifestContents["version"];
  const writeDistManifest = async (manifestObject) => {
    await Deno.writeTextFile("dist/vimium/manifest.json", JSON.stringify(manifestObject, null, 2));
  };
  // cd into "dist/vimium" before building the zip, so that the files in the zip don't each have the
  // path prefix "dist/vimium".
  // --filesync ensures that files in the archive which are no longer on disk are deleted. It's equivalent to
  // removing the zip file before the build.
  const zipCommand = "cd dist/vimium && zip -r --filesync ";

  await shell("rm", ["-rf", "dist/vimium"]);
  await shell("mkdir", ["-p", "dist/vimium", "dist/chrome-canary", "dist/chrome-store", "dist/firefox"]);
  await shell("rsync", rsyncOptions);

  // Firefox needs clipboardRead and clipboardWrite for commands like "copyCurrentUrl", but Chrome does not.
  // See #4186.
  const firefoxPermissions = Array.from(manifestContents.permissions);
  firefoxPermissions.push("clipboardRead");
  firefoxPermissions.push("clipboardWrite");

  writeDistManifest(Object.assign({}, manifestContents, {
    // Chrome considers this key invalid in manifest.json, so we add it only during the Firefox build phase.
    browser_specific_settings: {
      gecko: {
        strict_min_version: "62.0"
      },
    },
    permissions: firefoxPermissions,
  }));
  await shell("bash", ["-c", `${zipCommand} ../firefox/vimium-firefox-${vimiumVersion}.zip .`]);

  // Build the Chrome Store package.
  writeDistManifest(manifestContents);
  await shell("bash", ["-c", `${zipCommand} ../chrome-store/vimium-chrome-store-${vimiumVersion}.zip .`]);

  // Build the Chrome Store dev package.
  writeDistManifest(Object.assign({}, manifestContents, {
    name: "Vimium Canary",
    description: "This is the development branch of Vimium (it is beta software).",
  }));
  await shell("bash", ["-c", `${zipCommand} ../chrome-canary/vimium-canary-${vimiumVersion}.zip .`]);
}

const runUnitTests = async () => {
  // Import every test file.
  const dir = path.join(projectPath, "tests/unit_tests");
  const files = Array.from(Deno.readDirSync(dir)).map((f) => f.name).sort();
  for (let f of files) {
    if (f.endsWith("_test.js")) {
      await import(path.join(dir, f));
    }
  }

  await shoulda.run();
};

const runDomTests = async () => {
  const testFile = `${projectPath}/tests/dom_tests/dom_tests.html`;

  await (async () => {
    const browser = await puppeteer.launch({
      // NOTE(philc): "Disabling web security" is required for vomnibar_test.js, because we have a file://
      // page accessing an iframe, and Chrome prevents this because it's a cross-origin request.
      args: ['--disable-web-security']
    });

    const page = await browser.newPage();
    page.on("console", msg => console.log(msg.text()));
    page.on("error", (err) => console.log(err));
    page.on("pageerror", (err) => console.log(err));
    page.on('requestfailed', request =>
      console.log(console.log(`${request.failure().errorText} ${request.url()}`)));

    // Shoulda.js is an ECMAScript module, and those cannot be loaded over file:/// protocols due to a Chrome
    // security restriction, and this test suite loads the dom_tests.html page from the local file system. To
    // (painfully) work around this, we're injecting the contents of shoulda.js into the page. We munge the
    // file contents and assign it to a string (`shouldaJsContents`), and then have the page itself
    // document.write that string during load (the document.write call is in dom_tests.html).
    // Another workaround would be to spin up a local file server here and load dom_tests from the network.
    // Discussion: https://bugs.chromium.org/p/chromium/issues/detail?id=824651
    let shouldaJsContents =
      (await Deno.readTextFile("./tests/vendor/shoulda.js")) +
      "\n" +
      // Export the module contents to window.shoulda, which is what the tests expect.
      "window.shoulda = {assert, context, ensureCalled, getStats, reset, run, setup, should, stub, tearDown};";

    // Remove the `export` statement from the shoulda.js module. Because we're using document.write to add
    // this, an export statement will cause a JS error and halt further parsing.
    shouldaJsContents = shouldaJsContents.replace(/export {[^}]+}/, "");

    await page.evaluateOnNewDocument((content) => {
      window.shouldaJsContents = content;
    },
      shouldaJsContents);

    page.goto("file://" + testFile);

    await page.waitForNavigation({ waitUntil: "load" });

    const testsFailed = await page.evaluate(() => {
      shoulda.run();
      return shoulda.getStats().failed;
    });

    // NOTE(philc): At one point in development, I noticed that the output from Deno would suddenly pause,
    // prior to the tests fully finishing, so closing the browser here may be racy. If it occurs again, we may
    // need to add "await delay(200)".
    await browser.close();
    return testsFailed;
  })();
};

desc("Run unit tests");
task("test-unit", [], async () => {
  const failed = await runUnitTests();
  if (failed > 0)
    console.log("Failed:", failed);
});

desc("Run DOM tests");
task("test-dom", [], async () => {
  const failed = await runDomTests();
  if (failed > 0)
    console.log("Failed:", failed);
});

desc("Run unit and DOM tests");
task("test", [], async () => {
  const failed = (await runUnitTests()) + (await runDomTests());
  if (failed > 0)
    console.log("Failed:", failed);
});

desc("Builds a zip file for submission to the Chrome and Firefox stores. The output is in dist/");
task("package", [], async () => {
  await buildStorePackage();
});

run();

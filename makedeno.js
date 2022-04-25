#!/usr/bin/env deno run --allow-read --allow-write --allow-env --allow-net --allow-run --unstable
/*
 * This file is used like a Makefile.
 */
import * as fs from "https://deno.land/std/fs/mod.ts";
import * as fsCopy from "https://deno.land/std@0.122.0/fs/copy.ts";
import * as path from "https://deno.land/std@0.136.0/path/mod.ts";
import { delay } from 'https://deno.land/x/delay@v0.2.0/mod.ts';
import { desc, run, task, sh } from "https://deno.land/x/drake@v1.5.1/mod.ts";
import puppeteer from "https://deno.land/x/puppeteer@9.0.2/mod.ts";

const runUnitTests = async () => {
  // TODO(philc): Require all of the test files.
  await shoulda.run();
};

const runDomTests = async () => {
  const projectPath = new URL(".", import.meta.url).pathname;
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

    // We're injecting the contents of shoulda.js into the page. We'll munge the file contents and assign it
    // to a string, and then have the page itself document.write that string during load. This is a painful
    // workaround because shouldaJs is an ECMASCript module, and those cannot be loaded over file:///
    // protocols; this is a security restriction. This test suite loads the dom_tests.html page from the local
    // file system. Another workaround would be to spin up a local file server here and load dom_tests from
    // the network. Discussion: https://bugs.chromium.org/p/chromium/issues/detail?id=824651
    let shouldaJsContents =
        (await Deno.readTextFile("./tests/vendor/shoulda.js")) +
        "\n" +
        // Export the module contents to window.shoulda, which is what the tests expect.
        "window.shoulda = {assert, context, ensureCalled, getStats, reset, run, setup, should, stub, tearDown};";

    // Remove the `export` statement from the shoulda.js module. Because we're using document.write to add
    // this, an export statement will cause a JS error and halt parsing.
    shouldaJsContents = shouldaJsContents.replace(/export {[^}]+}/, "");

    await page.evaluateOnNewDocument(
      (content) => {
        window.shouldaJsContents = content;
      },
      shouldaJsContents
    );

    page.goto("file://" + testFile);

    await page.waitForNavigation({ waitUntil: "load" });

    const testsFailed = await page.evaluate(() => {
      shoulda.run();
      return shoulda.getStats().failed;
    });

    // NOTE(philc): At one point in development, I noticed that the tests would not finish before output
    // suddenly paused, so it may be racy. If occurs again, we may need to add "await delay(200)".
    await browser.close();
    return testsFailed;
  })();
};

task("test", [], async () => {
  const failed = await runDomTests();
  console.log("Test task");
  if (failed > 0)
    console.log("Failed:", failed);
});

await runDomTests();

// run();

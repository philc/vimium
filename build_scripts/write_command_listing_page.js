#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env
// Write a static version of the command_listing.html page to dist, to be hosted on vimium.github.io
// as an online reference.

import * as testHelper from "../tests/unit_tests/test_helper.js";
import "../tests/unit_tests/test_chrome_stubs.js";
import * as commandListing from "../pages/command_listing.js";
import * as fs from "@std/fs";
import * as path from "@std/path";

const scriptDir = path.dirname(path.fromFileUrl(import.meta.url));

chrome.storage.session.get = async (key) => {
  if (key == "commandToOptionsToKeys") {
    return { commandToOptionsToKeys: {} };
  }
};

await testHelper.jsdomStub(path.join(scriptDir, "../pages/command_listing.html"));
await Settings.onLoaded();

await commandListing.populatePage();

const dist = path.join(scriptDir, "../dist/command_listing_page");
if (await fs.exists(dist)) {
  await Deno.remove(dist, { recursive: true });
}

await Deno.mkdir(dist, { recursive: true });

// Write out all required CSS files to disk.
const linkEls = document.head.querySelectorAll("link[rel=stylesheet]");
for (const el of linkEls) {
  const cssPath = el.getAttribute("href");
  const src = path.join(scriptDir, "../pages/" + cssPath);
  const dest = path.join(dist, path.basename(cssPath));
  await Deno.copyFile(src, dest);
  el.setAttribute("href", path.basename(cssPath));
}

// Remove any external javascripts. Since this page's HTML has already been generated, it doesn't
// need JS at runtime.
for (const el of document.head.querySelectorAll("script")) {
  el.remove();
}

// Indicate that this is the hosted version of the page. This causes a link back to the
// Github repo to be shown.
document.querySelector("html").classList.add("hosted-version");

// Use the website's favicon.
const favicon = document.createElement("link");
favicon.setAttribute("rel", "shortcut icon");
favicon.href = "../vimium_logo.svg";
document.head.appendChild(favicon);

// The doctype tag is not included in outerHTML; add it back in.
const html = "<!DOCTYPE html>" + document.documentElement.outerHTML;
await Deno.writeTextFile(path.join(dist, "index.html"), html);

// A harness for end-to-end tests: it loads the real, unpacked extension into headless Chrome,
// serves test pages from a local server, sends real key presses, and reads back what the user would
// see. Run the tests with `./make.js test-e2e`.
//
// Each test file installs this harness's setup and teardown, which give each test a fresh Tab with
// default settings, and save a screenshot to failures/ when a test fails:
//
//   import * as e2e from "./harness.js";
//
//   context("link hints", () => {
//     setup(e2e.setup);
//     teardown(e2e.teardown);
//
//     should("follow a link", async ({ tab }) => {
//       await tab.load(`<a href="/fixtures/link_destination.html">link</a>`);
//       await tab.keys("f");
//       await tab.keys((await tab.hintMarkers())[0]);
//       await tab.waitFor(() => tab.path() == "/fixtures/link_destination.html");
//     });
//   });
//
// Much of Vimium is asynchronous, so check outcomes with tab.waitFor rather than reading state
// right after sending keys. Prefer asserting on what the user sees (the page, hint markers, the
// HUD, the Vomnibar) over Vimium's internal state.

import puppeteer from "puppeteer";
import * as path from "@std/path";
import * as fs from "@std/fs";
import * as fileServer from "@std/http/file-server";
import * as commands from "../../background_scripts/commands.js";

const e2eDir = path.dirname(path.fromFileUrl(import.meta.url));
const repoRoot = path.resolve(e2eDir, "../..");
const failuresDir = path.join(e2eDir, "failures");

const defaultTimeoutMs = 2000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Polls `fn` until it returns a truthy value, and returns that value. Throws if `timeoutMs` passes.
export async function waitFor(fn, { timeoutMs = defaultTimeoutMs, message } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (true) {
    const result = await fn();
    if (result) {
      return result;
    }
    if (Date.now() > deadline) {
      throw new Error(`Timed out after ${timeoutMs}ms waiting for ${message ?? fn.toString()}`);
    }
    await sleep(20);
  }
}

// Serves fixture files from tests/e2e_tests/fixtures at /fixtures/, and inline HTML strings
// registered by tests at /inline/<id>.
class FixtureServer {
  constructor() {
    this.inlinePages = new Map();
    this.nextInlineId = 1;
    this.server = Deno.serve({ port: 0, hostname: "127.0.0.1", onListen() {} }, (req) => {
      const url = new URL(req.url);
      if (url.pathname.startsWith("/inline/")) {
        const html = this.inlinePages.get(url.pathname);
        if (html == null) {
          return new Response("Not found", { status: 404 });
        }
        return new Response(html, { headers: { "content-type": "text/html; charset=utf-8" } });
      }
      if (url.pathname.startsWith("/fixtures/")) {
        return fileServer.serveDir(req, { fsRoot: e2eDir, quiet: true });
      }
      return new Response("Not found", { status: 404 });
    });
    this.port = this.server.addr.port;
  }

  // Two different origins pointing at the same server, for cross-origin iframe tests.
  url(pathname) {
    return `http://localhost:${this.port}${pathname}`;
  }

  crossOriginUrl(pathname) {
    return `http://127.0.0.1:${this.port}${pathname}`;
  }

  addInlinePage(html) {
    const pathname = `/inline/${this.nextInlineId++}.html`;
    this.inlinePages.set(pathname, html);
    return pathname;
  }

  async shutdown() {
    await this.server.shutdown();
  }
}

// Vim-style key names, as used in Vimium's key mappings, mapped to Puppeteer key names.
const namedKeys = {
  esc: "Escape",
  enter: "Enter",
  cr: "Enter",
  tab: "Tab",
  space: " ",
  backspace: "Backspace",
  bs: "Backspace",
  delete: "Delete",
  up: "ArrowUp",
  down: "ArrowDown",
  left: "ArrowLeft",
  right: "ArrowRight",
  home: "Home",
  end: "End",
  pageup: "PageUp",
  pagedown: "PageDown",
  lt: "<",
};
// Set the keys F1-F12.
for (let i = 1; i <= 12; i++) {
  namedKeys[`f${i}`] = `F${i}`;
}

const modifierKeys = { c: "Control", a: "Alt", m: "Meta", s: "Shift" };

// Parses a key sequence like "gg<c-f>G<esc>" into [{ key, modifiers }] of Puppeteer key names. The
// sequence is split into keys by the same parser Vimium uses for key mappings.
export function parseKeys(sequence) {
  return commands.KeyMappingsParser.parseKeySequence(sequence).map((token) => {
    if (token.length == 1) {
      return { key: token, modifiers: [] };
    }
    // A token like "<esc>", "<c-f>", or "<c-->". The parser has lowercased the modifiers and names.
    const [, modifierString, name] = token.match(/^<((?:[a-z]-)*)(.+)>$/);
    const modifiers = modifierString.split("-").filter((m) => m != "").map((m) => {
      const modifier = modifierKeys[m];
      if (!modifier) {
        throw new Error(`Unknown modifier "${m}" in key sequence "${sequence}"`);
      }
      return modifier;
    });
    const key = name.length == 1 ? name : namedKeys[name];
    if (!key) {
      throw new Error(`Unknown key "<${name}>" in key sequence "${sequence}"`);
    }
    return { key, modifiers };
  });
}

// One browser tab, with helpers for driving Vimium.
export class Tab {
  // `cdpSession` is a Chrome DevTools Protocol (CDP) session: the low-level connection Puppeteer
  // uses to control the browser. We use it directly for what Puppeteer's API doesn't expose, which
  // is running code inside Vimium's content scripts.
  constructor(harness, page, cdpSession) {
    this.harness = harness;
    this.page = page;
    this.cdpSession = cdpSession;
    // Content script execution contexts, by frame ID. These are the "isolated worlds" which
    // Chrome creates for extension content scripts.
    this.contentScriptContexts = new Map();
    cdpSession.on("Runtime.executionContextCreated", ({ context }) => {
      const aux = context.auxData ?? {};
      if (aux.type == "isolated" && context.origin.startsWith("chrome-extension://")) {
        this.contentScriptContexts.set(aux.frameId, context.id);
      }
    });
    cdpSession.on("Runtime.executionContextDestroyed", ({ executionContextId }) => {
      for (const [frameId, id] of this.contentScriptContexts) {
        if (id == executionContextId) {
          this.contentScriptContexts.delete(frameId);
        }
      }
    });
    cdpSession.on("Runtime.executionContextsCleared", () => this.contentScriptContexts.clear());
  }

  static async create(harness, page) {
    const cdpSession = await page.createCDPSession();
    const tab = new Tab(harness, page, cdpSession);
    await cdpSession.send("Runtime.enable");
    return tab;
  }

  // Loads a page and waits for Vimium to be ready in it. `page` is either an HTML string (served
  // from a local URL, since Vimium doesn't run on data: URLs), or a path to a file in
  // tests/e2e_tests/fixtures, e.g. "links.html".
  async load(page) {
    const pathname = page.trimStart().startsWith("<")
      ? this.harness.server.addInlinePage(page)
      : `/fixtures/${page}`;
    await this.page.goto(this.harness.server.url(pathname), { waitUntil: "load" });
    await this.page.bringToFront();
    await this.waitForVimium();
  }

  // Waits until Vimium's content script has initialized in the main frame and is handling keys.
  async waitForVimium() {
    await waitFor(async () => {
      try {
        return await this.evalInContentScript("globalThis.frameId != null");
      } catch {
        return false;
      }
    }, { timeoutMs: 5000, message: "Vimium's content script to initialize" });
  }

  // Evaluates a JavaScript expression in Vimium's content script, in the main frame. Prefer
  // asserting on what the user sees; this is an escape hatch for state that isn't visible.
  async evalInContentScript(expression) {
    const { frameTree } = await this.cdpSession.send("Page.getFrameTree");
    const contextId = this.contentScriptContexts.get(frameTree.frame.id);
    if (contextId == null) {
      throw new Error("Vimium's content script isn't loaded in this page.");
    }
    const { result, exceptionDetails } = await this.cdpSession.send("Runtime.evaluate", {
      expression,
      contextId,
      awaitPromise: true,
      returnByValue: true,
    });
    if (exceptionDetails) {
      throw new Error(`evalInContentScript failed: ${exceptionDetails.exception?.description}`);
    }
    return result.value;
  }

  // Evaluates a function in the page's own JavaScript context.
  async evaluate(fn, ...args) {
    return await this.page.evaluate(fn, ...args);
  }

  // Sends a sequence of key presses, using the notation of Vimium's key mappings:
  // "gg", "<c-f>", "<esc>", "<enter>", "<s-tab>".
  async keys(sequence) {
    for (const { key, modifiers } of parseKeys(sequence)) {
      for (const m of modifiers) {
        await this.page.keyboard.down(m);
      }
      await this.page.keyboard.press(key);
      for (const m of modifiers.toReversed()) {
        await this.page.keyboard.up(m);
      }
    }
  }

  // Types text into whatever has focus, e.g. the Vomnibar or the find-mode input.
  async type(text) {
    await this.page.keyboard.type(text);
  }

  url() {
    return this.page.url();
  }

  // The current URL's path, e.g. "/fixtures/link_destination.html".
  path() {
    return new URL(this.page.url()).pathname;
  }

  // Returns a URL on this test's server, for use in links within inline HTML. `crossOrigin` gives
  // the same path on a different origin.
  serverUrl(pathname, { crossOrigin = false } = {}) {
    const server = this.harness.server;
    return crossOrigin ? server.crossOriginUrl(pathname) : server.url(pathname);
  }

  // Returns the text of the visible link hint markers. Each frame draws the markers for its own
  // links, so this reads every frame: the main frame's markers first, in document order, then each
  // subframe's. Waits briefly for markers to appear, and returns [] if none do. Note that Vimium
  // also shows a marker for the body of each unfocused frame, so the frame can be focused.
  async hintMarkers({ timeoutMs = 1000 } = {}) {
    const read = async () => {
      const markers = [];
      for (const frame of this.page.frames()) {
        // Skip Vimium's own UI frames, like the HUD.
        if (frame.url().startsWith("chrome-extension://")) {
          continue;
        }
        const frameMarkers = await frame.$$eval(
          ".vimiumHintMarker",
          (els) =>
            els.filter((el) => getComputedStyle(el).display != "none")
              .map((el) => el.textContent.trim()),
        ).catch(() => []); // The frame may have navigated away or been detached.
        markers.push(...frameMarkers);
      }
      return markers;
    };
    try {
      return await waitFor(async () => {
        const markers = await read();
        return markers.length > 0 ? markers : null;
      }, { timeoutMs });
    } catch {
      return [];
    }
  }

  // Returns the frame of one of Vimium's UI components (HUD, Vomnibar, help dialog) if it's
  // visible, or null.
  async visibleUIComponentFrame(className) {
    const iframe = await this.page.$(`>>> iframe.${className}.vimium-ui-component-visible`);
    return iframe ? await iframe.contentFrame() : null;
  }

  // Returns { text, findMode } for the HUD, or null if the HUD isn't showing. `findMode` is true
  // when find mode's input is showing and focused, i.e. ready to be typed into. `text` includes the
  // find query and match count.
  async hud() {
    const frame = await this.visibleUIComponentFrame("vimium-hud-frame");
    if (!frame) {
      return null;
    }
    return await frame.$eval("#hud", (el) => ({
      text: el.textContent.trim(),
      findMode: el.classList.contains("hud-find") && document.hasFocus() &&
        document.activeElement?.id == "hud-find-input",
    }));
  }

  // Returns { query, completions } for the Vomnibar, or null if it isn't showing. `completions`
  // holds the text of each completion item.
  async vomnibar() {
    const frame = await this.visibleUIComponentFrame("vomnibar-frame");
    if (!frame) {
      return null;
    }
    return await frame.evaluate(() => ({
      query: document.querySelector("#vomnibar input").value,
      completions: Array.from(document.querySelectorAll("#vomnibar li"))
        .map((li) => li.textContent.trim()),
    }));
  }

  // Waits for an async predicate to become truthy, and returns its value.
  async waitFor(fn, options) {
    return await waitFor(fn, options);
  }

  async screenshot(filePath) {
    await this.page.screenshot({ path: filePath });
  }
}

// Contains the browser, the extension's background service worker, and the fixture server.
export class Harness {
  static async launch({ headless = true } = {}) {
    const harness = new Harness();
    harness.server = new FixtureServer();
    harness.browser = await puppeteer.launch({
      headless,
      args: [
        `--disable-extensions-except=${repoRoot}`,
        `--load-extension=${repoRoot}`,
      ],
    });
    const workerTarget = await harness.browser.waitForTarget(
      (t) => t.type() == "service_worker" && t.url().includes("background_scripts/main.js"),
      { timeout: 10000 },
    );
    harness.worker = await workerTarget.worker();
    harness.extensionId = new URL(workerTarget.url()).host;
    return harness;
  }

  // Evaluates a function in the extension's background service worker.
  async evalInBackground(fn, ...args) {
    return await this.worker.evaluate(fn, ...args);
  }

  // Sets Vimium's settings to the defaults plus `overrides`, and waits for the background page to
  // apply them. Content scripts read settings when a page loads, so call this before Tab.load.
  async setSettings(overrides = {}) {
    await this.evalInBackground(async (overrides) => {
      const Settings = globalThis.Settings;
      await Settings.onLoaded();
      const current = Settings.getSettings();
      // Without settingsVersion, Settings would treat this as pre-2.0 settings and migrate them.
      const desired = Object.assign(structuredClone(Settings.defaultOptions), overrides, {
        settingsVersion: current.settingsVersion,
      });
      const isUnchanged = Object.keys(desired)
        .every((k) => JSON.stringify(desired[k]) == JSON.stringify(current[k]));
      if (isUnchanged) {
        return;
      }
      // The background page re-parses key mappings asynchronously after a settings change, and
      // publishes them to session storage. Wait for that, so the next page load sees them.
      const getKeyState = async () =>
        JSON.stringify(
          (await chrome.storage.session.get("normalModeKeyStateMapping")).normalModeKeyStateMapping,
        );
      const keyStateBefore = await getKeyState();
      await Settings.setSettings(desired);
      if (desired.keyMappings != current.keyMappings) {
        const deadline = Date.now() + 1000;
        while (await getKeyState() == keyStateBefore && Date.now() < deadline) {
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
      }
    }, overrides);
  }

  // Returns the URLs of all open tabs.
  async tabUrls() {
    return await this.evalInBackground(async () =>
      (await chrome.tabs.query({})).map((tab) => tab.url)
    );
  }

  // Resets state between tests: default settings, and a single fresh tab.
  async newTab() {
    await this.setSettings({});
    const oldPages = await this.browser.pages();
    const page = await this.browser.newPage();
    for (const p of oldPages) {
      await p.close();
    }
    return await Tab.create(this, page);
  }

  async close() {
    await this.browser.close();
    await this.server.shutdown();
  }
}

// The harness is shared by every test in a run.
let currentHarness = null;

export async function getHarness() {
  if (currentHarness == null) {
    currentHarness = await Harness.launch();
  }
  return currentHarness;
}

export async function closeHarness() {
  if (currentHarness == null) {
    return;
  }
  await currentHarness.close();
  currentHarness = null;
}

// A shoulda setup function which gives each test a fresh tab, as `tab` on the test's scope.
export async function setup(scope) {
  const harness = await getHarness();
  scope.tab = await harness.newTab();
}

// A shoulda teardown function which saves a screenshot to tests/e2e_tests/failures/ when a test has
// failed.
export async function teardown(scope, testInfo) {
  if (testInfo.errors.length == 0 || scope.tab == null) {
    return;
  }
  await fs.ensureDir(failuresDir);
  const fileName = testInfo.name.replace(/[^a-z0-9]+/gi, "_").slice(0, 120) + ".png";
  const screenshotPath = path.join(failuresDir, fileName);
  try {
    await scope.tab.screenshot(screenshotPath);
    console.log(`Screenshot of the failure: ${path.relative(Deno.cwd(), screenshotPath)}`);
  } catch {
    // The page may have closed or crashed; the test's own error is what matters.
  }
}

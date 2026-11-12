import "./test_helper.js";
import "../../lib/settings.js";
import * as gistSync from "../../background_scripts/gist_sync.js";

const gistId = "abc123";
const token = "test-token";

// Replaces globalThis.fetch with a stub which records requests, and responds using `handler`.
const stubFetch = (handler) => {
  const requests = [];
  stub(globalThis, "fetch", (url, options) => {
    requests.push({ url, ...options, body: options.body ? JSON.parse(options.body) : null });
    const { status = 200, json = {}, text = "" } = handler(url, options) || {};
    return Promise.resolve({
      ok: status >= 200 && status < 300,
      status,
      statusText: "",
      json: () => Promise.resolve(json),
      text: () => Promise.resolve(text),
    });
  });
  return requests;
};

const assertRejects = async (fn) => {
  let error = null;
  try {
    await fn();
  } catch (e) {
    error = e;
  }
  assert.isTrue(error != null);
};

context("gist sync", () => {
  setup(async () => {
    await Settings.onLoaded();
    await gistSync.setConfig({ token, gistId, autoUpload: false, status: null, lastContent: null });
  });

  teardown(async () => {
    await Settings.clear();
    await chrome.storage.local.clear();
  });

  should("parse gist IDs from URLs", () => {
    assert.equal(gistId, gistSync.parseGistId(gistId));
    assert.equal(gistId, gistSync.parseGistId(` https://gist.github.com/someone/${gistId}/ `));
  });

  should("upload settings to the gist", async () => {
    await Settings.set("keyMappings", "map a scrollUp");
    const requests = stubFetch(() => ({}));
    await gistSync.upload();
    assert.equal(1, requests.length);
    const request = requests[0];
    assert.equal(`https://api.github.com/gists/${gistId}`, request.url);
    assert.equal("PATCH", request.method);
    assert.equal(`Bearer ${token}`, request.headers["Authorization"]);
    const content = request.body.files[gistSync.GIST_FILE_NAME].content;
    assert.equal("map a scrollUp", JSON.parse(content).keyMappings);
    assert.isTrue((await gistSync.getConfig()).status.ok);
  });

  should("not include the token in the settings or the uploaded content", async () => {
    const requests = stubFetch(() => ({}));
    await gistSync.upload();
    assert.isFalse(requests[0].body.files[gistSync.GIST_FILE_NAME].content.includes(token));
    assert.isFalse(JSON.stringify(Settings.getSettings()).includes(token));
  });

  should("create a secret gist containing the settings", async () => {
    await gistSync.setConfig({ gistId: "" });
    await Settings.set("keyMappings", "map a scrollUp");
    const requests = stubFetch(() => ({ json: { id: "newgist", public: false } }));
    assert.equal("newgist", await gistSync.createGist());
    const request = requests[0];
    assert.equal("https://api.github.com/gists", request.url);
    assert.equal("POST", request.method);
    assert.equal(false, request.body.public);
    const content = request.body.files[gistSync.GIST_FILE_NAME].content;
    assert.equal("map a scrollUp", JSON.parse(content).keyMappings);
    assert.equal("newgist", (await gistSync.getConfig()).gistId);
  });

  should("restore settings from the gist", async () => {
    const content = JSON.stringify({ keyMappings: "map b scrollDown", settingsVersion: "2.4.2" });
    stubFetch(() => ({ json: { files: { [gistSync.GIST_FILE_NAME]: { content } } } }));
    await gistSync.download();
    assert.equal("map b scrollDown", Settings.get("keyMappings"));
  });

  should("fetch the raw content when the gist file is truncated", async () => {
    const rawUrl = "https://gist.githubusercontent.com/raw/vimium-options.json";
    const requests = stubFetch((url) => {
      if (url == rawUrl) {
        return {
          text: JSON.stringify({ keyMappings: "map c scrollUp", settingsVersion: "2.4.2" }),
        };
      }
      return {
        json: {
          files: { [gistSync.GIST_FILE_NAME]: { truncated: true, content: "{", raw_url: rawUrl } },
        },
      };
    });
    await gistSync.download();
    assert.equal(rawUrl, requests[1].url);
    assert.equal("map c scrollUp", Settings.get("keyMappings"));
  });

  should("list the gist's recent revisions", async () => {
    const history = Array.from({ length: 12 }, (_, i) => ({
      version: `v${i}`,
      committed_at: "2026-10-12T00:00:00Z",
      change_status: { additions: i, deletions: 1 },
    }));
    stubFetch(() => ({ json: { history } }));
    const revisions = await gistSync.listRevisions();
    assert.equal(10, revisions.length);
    assert.equal(
      { version: "v1", committedAt: "2026-10-12T00:00:00Z", additions: 1, deletions: 1 },
      revisions[1],
    );
  });

  should("restore settings from an earlier revision", async () => {
    const content = JSON.stringify({ keyMappings: "map d scrollUp", settingsVersion: "2.4.2" });
    const requests = stubFetch(() => ({
      json: { files: { [gistSync.GIST_FILE_NAME]: { content } } },
    }));
    await gistSync.restoreRevision("abcdef123456");
    assert.equal(`https://api.github.com/gists/${gistId}/abcdef123456`, requests[0].url);
    assert.equal("map d scrollUp", Settings.get("keyMappings"));
    // The gist's latest version still differs, so auto-upload should upload the restored settings.
    await gistSync.setConfig({ autoUpload: true });
    assert.isTrue(await gistSync.autoUploadIfChanged());
  });

  should("raise an error when the gist has no settings file", async () => {
    stubFetch(() => ({ json: { files: { "README.md": { content: "" } } } }));
    await assertRejects(() => gistSync.download());
    assert.isFalse((await gistSync.getConfig()).status.ok);
  });

  should("raise an error when the GitHub API returns an error", async () => {
    stubFetch(() => ({ status: 401, json: { message: "Bad credentials" } }));
    await assertRejects(() => gistSync.upload());
    assert.isTrue((await gistSync.getConfig()).status.message.includes("Bad credentials"));
  });

  should("not auto-upload when auto-upload is disabled", async () => {
    const requests = stubFetch(() => ({}));
    assert.isFalse(await gistSync.autoUploadIfChanged());
    assert.equal(0, requests.length);
  });

  should("auto-upload only when the settings have changed", async () => {
    await gistSync.setConfig({ autoUpload: true });
    const requests = stubFetch(() => ({}));
    assert.isTrue(await gistSync.autoUploadIfChanged());
    assert.isFalse(await gistSync.autoUploadIfChanged());
    await Settings.set("keyMappings", "map a scrollUp");
    assert.isTrue(await gistSync.autoUploadIfChanged());
    assert.equal(2, requests.length);
  });
});

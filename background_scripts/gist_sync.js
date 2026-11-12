// Syncs Vimium's settings to and from a GitHub Gist, using the same JSON format as the backup file
// on the options page.
//
// The token and gist ID are stored in chrome.storage.local, never in chrome.storage.sync: everything
// in storage.sync is treated as a Vimium setting, and would end up in backups and in the gist.

export const GIST_FILE_NAME = "vimium-options.json";

const apiBaseUrl = "https://api.github.com";
const autoUploadDelayMs = 3000;

const configKeys = {
  token: "gistSyncToken",
  gistId: "gistSyncId",
  autoUpload: "gistSyncAutoUpload",
  status: "gistSyncStatus",
  // The content most recently uploaded to or downloaded from the gist. Used to skip redundant
  // auto-uploads.
  lastContent: "gistSyncLastContent",
};

export async function getConfig() {
  const result = await chrome.storage.local.get(Object.values(configKeys));
  return {
    token: result[configKeys.token] || "",
    gistId: result[configKeys.gistId] || "",
    autoUpload: result[configKeys.autoUpload] || false,
    status: result[configKeys.status] || null,
    lastContent: result[configKeys.lastContent] || null,
  };
}

export async function setConfig(config) {
  const items = {};
  for (const [k, v] of Object.entries(config)) {
    if (!(k in configKeys)) throw new Error(`Unknown gist sync config key: ${k}`);
    items[configKeys[k]] = v;
  }
  await chrome.storage.local.set(items);
}

// Accepts either a bare gist ID or a gist URL like https://gist.github.com/user/<id>.
export function parseGistId(str) {
  const trimmed = (str || "").trim().replace(/\/+$/, "");
  return trimmed.split("/").pop().split("#")[0];
}

// Returns the settings as the JSON string used for both backup files and the gist.
export function serializeSettings(settings) {
  settings = Settings.pruneOutDefaultValues(settings);
  // Serialize the JSON keys in order, so that they're stable across backups. See #4764.
  const keys = Object.keys(settings).sort();
  const sortedSettings = Object.fromEntries(keys.map((k) => [k, settings[k]]));
  // Don't use an array replacer in JSON.stringify; it filters nested object keys too, which would
  // drop nested fields inside exclusionRules (e.g. `pattern`, `passKeys`). See #4853.
  return JSON.stringify(sortedSettings, null, 2) + "\n";
}

async function githubRequest(token, method, url, body) {
  const response = await fetch(url.startsWith("https://") ? url : apiBaseUrl + url, {
    method,
    cache: "no-store",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    let message = response.statusText;
    try {
      message = (await response.json()).message || message;
    } catch {
      // The error body isn't JSON; use the status text.
    }
    throw new Error(`GitHub API error ${response.status}: ${message}`);
  }
  return response;
}

async function getRequiredConfig() {
  const config = await getConfig();
  if (!config.token) throw new Error("No GitHub token has been configured.");
  if (!config.gistId) throw new Error("No gist ID has been configured.");
  return config;
}

async function recordStatus(ok, message) {
  await setConfig({ status: { time: new Date().toISOString(), ok, message } });
}

async function fetchGist(config) {
  const response = await githubRequest(config.token, "GET", `/gists/${config.gistId}`);
  return await response.json();
}

// Returns the content of the settings file in the gist, or null if the gist doesn't have one.
async function fetchGistFileContent(config, gist) {
  const file = gist.files?.[GIST_FILE_NAME];
  if (!file) return null;
  if (!file.truncated) return file.content;
  // The API truncates large files; fetch the full content from the raw URL instead.
  const response = await githubRequest(config.token, "GET", file.raw_url);
  return await response.text();
}

// Checks that the token and gist are usable. Returns a human-readable description of the result.
export async function testConnection() {
  try {
    const config = await getRequiredConfig();
    const gist = await fetchGist(config);
    const messages = [];
    messages.push(
      gist.files?.[GIST_FILE_NAME]
        ? `Connected. The gist contains ${GIST_FILE_NAME}.`
        : `Connected. The gist doesn't contain ${GIST_FILE_NAME} yet; upload to create it.`,
    );
    if (gist.public) {
      messages.push("Warning: this gist is public, so anyone can read your settings.");
    }
    const message = messages.join(" ");
    await recordStatus(true, message);
    return message;
  } catch (error) {
    await recordStatus(false, error.message);
    throw error;
  }
}

// Creates a new secret gist containing the current settings, and saves its ID in the config.
// Returns the new gist's ID.
export async function createGist() {
  try {
    const config = await getConfig();
    if (!config.token) throw new Error("No GitHub token has been configured.");
    await Settings.onLoaded();
    const content = serializeSettings(Settings.getSettings());
    const response = await githubRequest(config.token, "POST", "/gists", {
      description: "Vimium settings",
      public: false,
      files: { [GIST_FILE_NAME]: { content } },
    });
    const gist = await response.json();
    if (!gist.id) throw new Error("GitHub did not return a gist ID.");
    await setConfig({ gistId: gist.id, lastContent: content });
    await recordStatus(true, "Created a secret gist and uploaded your settings to it.");
    return gist.id;
  } catch (error) {
    await recordStatus(false, `Creating a gist failed: ${error.message}`);
    throw error;
  }
}

// Uploads the current settings to the gist. Other files in the gist are left untouched.
export async function upload() {
  try {
    const config = await getRequiredConfig();
    await Settings.onLoaded();
    const content = serializeSettings(Settings.getSettings());
    await githubRequest(config.token, "PATCH", `/gists/${config.gistId}`, {
      files: { [GIST_FILE_NAME]: { content } },
    });
    await setConfig({ lastContent: content });
    await recordStatus(true, "Uploaded settings to the gist.");
  } catch (error) {
    await recordStatus(false, `Upload failed: ${error.message}`);
    throw error;
  }
}

// Parses the settings file in `gist` and replaces the current settings with it.
async function applySettingsFromGist(config, gist) {
  const content = await fetchGistFileContent(config, gist);
  if (content == null) throw new Error(`The gist doesn't contain ${GIST_FILE_NAME}.`);
  let settings;
  try {
    settings = JSON.parse(content);
  } catch (error) {
    throw new Error(`Failed to parse ${GIST_FILE_NAME}: ${error.message}`);
  }
  await Settings.setSettings(settings);
}

// Replaces the current settings with the ones stored in the gist.
export async function download() {
  try {
    const config = await getRequiredConfig();
    const gist = await fetchGist(config);
    await applySettingsFromGist(config, gist);
    // Record what's now stored, so that auto-upload doesn't immediately re-upload these settings.
    await setConfig({ lastContent: serializeSettings(Settings.getSettings()) });
    await recordStatus(true, "Restored settings from the gist.");
  } catch (error) {
    await recordStatus(false, `Restore failed: ${error.message}`);
    throw error;
  }
}

// Returns the gist's most recent revisions, newest first, as a list of
// {version, committedAt, additions, deletions}.
export async function listRevisions(limit = 10) {
  const config = await getRequiredConfig();
  const gist = await fetchGist(config);
  return (gist.history || []).slice(0, limit).map((item) => ({
    version: item.version,
    committedAt: item.committed_at,
    additions: item.change_status?.additions || 0,
    deletions: item.change_status?.deletions || 0,
  }));
}

// Replaces the current settings with the ones stored in an earlier revision of the gist. Unlike
// download(), this leaves lastContent alone: the gist still holds newer settings, so if auto-upload
// is enabled, the restored settings are uploaded as a new revision.
export async function restoreRevision(version) {
  try {
    const config = await getRequiredConfig();
    const response = await githubRequest(
      config.token,
      "GET",
      `/gists/${config.gistId}/${version}`,
    );
    await applySettingsFromGist(config, await response.json());
    await recordStatus(true, `Restored settings from revision ${version.slice(0, 7)}.`);
  } catch (error) {
    await recordStatus(false, `Restore failed: ${error.message}`);
    throw error;
  }
}

let autoUploadTimer = null;

// Uploads the settings if auto-upload is enabled and they've changed since the last sync. Errors are
// recorded in the status rather than thrown; the settings themselves are already saved locally.
export async function autoUploadIfChanged() {
  const config = await getConfig();
  if (!config.autoUpload || !config.token || !config.gistId) return false;
  await Settings.onLoaded();
  const content = serializeSettings(Settings.getSettings());
  if (content == config.lastContent) return false;
  try {
    await upload();
    return true;
  } catch (error) {
    console.warn("Vimium: auto-upload to gist failed:", error);
    return false;
  }
}

// Called by the background page when settings change. Debounced so that a burst of changes results
// in a single upload.
export function onSettingsChanged() {
  clearTimeout(autoUploadTimer);
  autoUploadTimer = setTimeout(() => autoUploadIfChanged(), autoUploadDelayMs);
}

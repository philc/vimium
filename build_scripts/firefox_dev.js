// Runs Firefox for development, with this checkout of Vimium installed as a temporary add-on. Used
// by `./make.js run-firefox-dev`.
//
// Firefox removes temporary add-ons when it quits, so this is meant to be run again whenever you
// want Vimium (re)loaded:
// - If the dev Firefox isn't running, this launches it, then installs Vimium.
// - If it's running, this installs Vimium again, which reloads it.
//
// The dev Firefox uses its own profile, which persists across runs, so other extensions installed
// in it from addons.mozilla.org stay installed. It talks to Firefox over the Firefox remote
// debugging protocol, which is what about:debugging and Mozilla's web-ext tool use:
// https://firefox-source-docs.mozilla.org/devtools/backend/protocol.html

import * as path from "@std/path";

// While the dev Firefox runs, any local process can control it through this port.
const debuggerPort = 6077;

// The profile is outside the repo, so `git clean -x` doesn't delete logins saved in it. All
// worktrees share it.
const profileDir = path.join(Deno.env.get("HOME"), ".local/share/vimium/firefox-dev-profile");

// Prefs which let this script connect to Firefox's debugger server without a prompt.
const profilePrefs = {
  "devtools.debugger.remote-enabled": true,
  "devtools.chrome.enabled": true,
  "devtools.debugger.prompt-connection": false,
  "browser.shell.checkDefaultBrowser": false,
};

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// A minimal client for the Firefox remote debugging protocol. Each packet is a JSON object
// prefixed by its length in bytes and a colon, e.g. `22:{"to":"root","type":"x"}`.
class DebuggerClient {
  constructor(conn) {
    this.conn = conn;
    this.buffer = new Uint8Array(0);
  }

  static async connect() {
    const conn = await Deno.connect({ hostname: "127.0.0.1", port: debuggerPort });
    const client = new DebuggerClient(conn);
    // The server sends a greeting from the root actor when a client connects.
    await client.readPacket();
    return client;
  }

  async readPacket() {
    while (true) {
      const colon = this.buffer.indexOf(":".charCodeAt(0));
      if (colon != -1) {
        const length = Number(new TextDecoder().decode(this.buffer.slice(0, colon)));
        const packetEnd = colon + 1 + length;
        if (this.buffer.length >= packetEnd) {
          const json = new TextDecoder().decode(this.buffer.slice(colon + 1, packetEnd));
          this.buffer = this.buffer.slice(packetEnd);
          return JSON.parse(json);
        }
      }
      const chunk = new Uint8Array(64 * 1024);
      const n = await this.conn.read(chunk);
      if (n == null) {
        throw new Error("Firefox closed the debugger connection.");
      }
      this.buffer = new Uint8Array([...this.buffer, ...chunk.subarray(0, n)]);
    }
  }

  // Sends a request to an actor, and returns its reply. Actors can also send unsolicited events,
  // so this skips packets from other actors, and packets which carry a "type" (events, not
  // replies).
  async request(packet) {
    const json = new TextEncoder().encode(JSON.stringify(packet));
    const prefix = new TextEncoder().encode(`${json.length}:`);
    await this.conn.write(new Uint8Array([...prefix, ...json]));
    while (true) {
      const reply = await this.readPacket();
      if (reply.from != packet.to || reply.type) {
        continue;
      }
      if (reply.error) {
        throw new Error(`Firefox: ${reply.error}: ${reply.message}`);
      }
      return reply;
    }
  }

  close() {
    this.conn.close();
  }
}

async function tryConnect() {
  try {
    return await DebuggerClient.connect();
  } catch (e) {
    if (e instanceof Deno.errors.ConnectionRefused) {
      return null;
    }
    throw e;
  }
}

async function launchFirefox() {
  await Deno.mkdir(profileDir, { recursive: true });
  const userJs = Object.entries(profilePrefs)
    .map(([name, value]) => `user_pref(${JSON.stringify(name)}, ${JSON.stringify(value)});\n`)
    .join("");
  await Deno.writeTextFile(path.join(profileDir, "user.js"), userJs);

  const firefoxArgs = ["-profile", profileDir, "-start-debugger-server", String(debuggerPort)];
  if (Deno.build.os == "darwin") {
    // Launching through `open` makes it a normal app launch, independent of this process. -n starts
    // a new instance even if another Firefox, e.g. one with your usual profile, is already running.
    const command = new Deno.Command("open", {
      args: ["-n", "-a", "Firefox", "--args", ...firefoxArgs],
    });
    const status = await command.output();
    if (!status.success) {
      throw new Error("Couldn't launch Firefox with `open -a Firefox`.");
    }
  } else {
    const command = new Deno.Command("firefox", {
      args: firefoxArgs,
      stdin: "null",
      stdout: "null",
      stderr: "null",
    });
    command.spawn().unref();
  }
}

async function connectOrLaunch() {
  const client = await tryConnect();
  if (client) {
    return client;
  }
  console.log("Launching Firefox with the profile in", profileDir);
  await launchFirefox();
  const timeoutMs = 30_000;
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    await sleep(250);
    const client = await tryConnect();
    if (client) {
      return client;
    }
  }
  throw new Error(`Firefox's debugger server didn't start on port ${debuggerPort}.`);
}

export async function run(extensionDir) {
  const client = await connectOrLaunch();
  try {
    const root = await client.request({ to: "root", type: "getRoot" });
    // Installing a temporary add-on which is already installed reloads it.
    const reply = await client.request({
      to: root.addonsActor,
      type: "installTemporaryAddon",
      addonPath: extensionDir,
      openDevTools: false,
    });
    console.log(`Installed ${extensionDir} as ${reply.addon.id}.`);
  } finally {
    client.close();
  }
}

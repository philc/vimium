# Vimium Codebase Guide: Adding New Features (e.g. `y`-Key Commands)

This guide provides an overview of Vimium's architecture, explains how key sequences (like
`y`-prefixed yank commands) work under the hood, highlights key files to visit, and walks through
implementing new commands step-by-step.

---

## 1. Architecture Overview

Vimium is divided into two primary execution environments that communicate through Chrome's runtime
messaging APIs:

```
┌─────────────────────────────────────────────────────────────┐
│                    Content Scripts                          │
│               (Injected into each web tab)                  │
│                                                             │
│  - Captures keyboard events via mode stack                  │
│  - Mode handlers: Normal, Visual, Link Hints, Find, Insert  │
│  - DOM manipulations, scrolling, clicking, focus            │
│  - Displays HUD (Heads-Up Display) and link hint markers    │
└───────────────────────────▲─────────────────────────────────┘
                            │
               chrome.runtime.sendMessage
               chrome.tabs.sendMessage
               chrome.storage.session
                            │
┌───────────────────────────▼─────────────────────────────────┐
│                   Background Scripts                        │
│               (Extension Service Worker)                    │
│                                                             │
│  - Browser-level operations: tabs, windows, history, marks  │
│  - Settings & custom keymapping parsing                     │
│  - Compiles key sequence tries into storage                 │
│  - Vomnibar autocompletion engines                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. How Multi-Key Sequences (e.g., `y` + letter) Work

In Vim / Vimium, `y` stands for **yank** (copy) or actions like duplicate tab (`yt`):

- `yy` &rarr;
  [`copyCurrentUrl`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js#L177-L188)
  (copies current page URL to clipboard)
- `yl` &rarr;
  [`yankClosestLink`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js) (copies
  URL of the link closest to the mouse cursor)
- `yc` &rarr;
  [`yankClosestCode`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js) (copies
  the code snippet closest to the mouse cursor in apps like Gemini, Claude, ChatGPT, GitHub)
- `y` or `Y` &rarr;
  [`yankPageOrLines`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js) (copies
  whole page contents; or with a count prefix like `5y`, copies 5 lines below the cursor)
- `yf` &rarr;
  [`LinkHints.activateModeToCopyLinkUrl`](file:///home/vaseline/Projects/vimium/content_scripts/link_hints.js#L345-L352)
  (shows link hints and copies selected link URL)
- `yt` &rarr;
  [`duplicateTab`](file:///home/vaseline/Projects/vimium/background_scripts/main.js#L299-L303)
  (duplicates current browser tab)

### Keystroke Execution Flow:

1. **Compilation into a Trie**: When Vimium starts (or key mappings change),
   [`Commands.installKeyStateMapping`](file:///home/vaseline/Projects/vimium/background_scripts/commands.js#L333-L356)
   builds a nested dictionary trie stored in `chrome.storage.session.normalModeKeyStateMapping`:
   ```javascript
   {
     "y": {
       "command": "yankPageOrLines",
       "y": { "command": "copyCurrentUrl", "noRepeat": true },
       "l": { "command": "yankClosestLink", "noRepeat": true },
       "c": { "command": "yankClosestCode", "noRepeat": true },
       "f": { "command": "LinkHints.activateModeToCopyLinkUrl" },
       "t": { "command": "duplicateTab" }
     }
   }
   ```
2. **Key Capture**: When you type `y`,
   [`KeyHandlerMode.onKeydown`](file:///home/vaseline/Projects/vimium/content_scripts/mode_key_handler.js#L60-L85)
   receives the event.
3. **State Advancement**:
   [`KeyHandlerMode.handleKeyChar`](file:///home/vaseline/Projects/vimium/content_scripts/mode_key_handler.js#L123-L146)
   matches `y`, advances its internal state to the subtree under `y`, suppresses browser default
   handling, and waits for the next keypress.
4. **Command Dispatch**: When you type the next letter (e.g., `y`, `f`, `t`, or your new key), it
   reaches a leaf node containing the `command` property and invokes
   [`NormalMode.commandHandler`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js#L33-L76).
5. **Execution**:
   - If `registryEntry.background === true`, it sends a message (`runBackgroundCommand`) to
     `BackgroundCommands` in
     [`background_scripts/main.js`](file:///home/vaseline/Projects/vimium/background_scripts/main.js).
   - Otherwise, it executes the handler directly from `NormalModeCommands` in
     [`content_scripts/mode_normal.js`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js).

---

## 3. Directory Map & Key Files

### Core Files

| File Path                                                                                                            | Description                                                                               |
| :------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------- |
| [`background_scripts/all_commands.js`](file:///home/vaseline/Projects/vimium/background_scripts/all_commands.js)     | Central registry of all command definitions, descriptions, groups, and options.           |
| [`background_scripts/commands.js`](file:///home/vaseline/Projects/vimium/background_scripts/commands.js)             | Defines `defaultKeyMappings`, parses custom user mappings, and builds the key state trie. |
| [`content_scripts/mode_normal.js`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js)             | Implements normal mode logic and contains `NormalModeCommands` (DOM/frontend commands).   |
| [`content_scripts/hud.js`](file:///home/vaseline/Projects/vimium/content_scripts/hud.js)                             | HUD UI helper for `HUD.copyToClipboard(...)` and `HUD.show(...)` toast notifications.     |
| [`content_scripts/link_hints.js`](file:///home/vaseline/Projects/vimium/content_scripts/link_hints.js)               | Interactive link hints system (for selecting links/elements using typed letters).         |
| [`background_scripts/main.js`](file:///home/vaseline/Projects/vimium/background_scripts/main.js)                     | Background script entry point containing `BackgroundCommands` (tab/window operations).    |
| [`background_scripts/tab_operations.js`](file:///home/vaseline/Projects/vimium/background_scripts/tab_operations.js) | Helper functions for creating, closing, and manipulating tabs.                            |
| [`tests/unit_tests/commands_test.js`](file:///home/vaseline/Projects/vimium/tests/unit_tests/commands_test.js)       | Unit test suite for verifying command mapping and parsing.                                |

---

## 4. Step-by-Step Tutorial: Implementing a New `y`-Command

Suppose you want to add a feature **`ym`** that copies the current page's title and URL in
**Markdown format** (`[Page Title](URL)`).

### Step 1: Register the Command Definition

Open
[`background_scripts/all_commands.js`](file:///home/vaseline/Projects/vimium/background_scripts/all_commands.js)
and add your command object into `allCommands`:

```javascript
{
  name: "copyCurrentMarkdownLink",
  desc: "Copy the current page title and URL as a Markdown link",
  group: "navigation",
  noRepeat: true,
},
```

### Step 2: Add the Default Key Mapping

Open
[`background_scripts/commands.js`](file:///home/vaseline/Projects/vimium/background_scripts/commands.js#L422)
and bind your key sequence in `defaultKeyMappings`:

```javascript
"yy": "copyCurrentUrl",
"ym": "copyCurrentMarkdownLink", // <-- Your new key binding
"p": "openCopiedUrlInCurrentTab",
```

### Step 3: Implement the Command Logic

#### Option A: Frontend / DOM Command (Recommended for page content & clipboard)

Open
[`content_scripts/mode_normal.js`](file:///home/vaseline/Projects/vimium/content_scripts/mode_normal.js)
and add the method inside `NormalModeCommands`:

```javascript
copyCurrentMarkdownLink() {
  chrome.runtime.sendMessage({ handler: "getCurrentTabUrl" }, function (url) {
    const title = document.title || url;
    const markdown = `[${title}](${url})`;
    HUD.copyToClipboard(markdown);
    HUD.show(`Yanked markdown link: ${title}`, 2000);
  });
},
```

#### Option B: Background Command (For tabs, windows, bookmarks, or browser state)

If your command needs access to `chrome.tabs.*` or `chrome.windows.*` APIs:

1. In
   [`background_scripts/all_commands.js`](file:///home/vaseline/Projects/vimium/background_scripts/all_commands.js),
   set `background: true`.
2. In
   [`background_scripts/main.js`](file:///home/vaseline/Projects/vimium/background_scripts/main.js),
   add the handler under `BackgroundCommands`:
   ```javascript
   copyAllTabUrls: async (_request) => {
     const tabs = await chrome.tabs.query({ currentWindow: true });
     const urls = tabs.map((t) => t.url).join("\n");
     // Send to HUD or clipboard
   },
   ```

---

## 5. Development, Testing & Verification

### Running Tests

The project uses Deno and Drake tasks:

```bash
# Run unit tests
./make.js test-unit

# Check formatting and linting
./make.js check

# Run all tests (unit + headless DOM tests)
./make.js test
```

### Loading Unpacked in Chrome / Edge

1. Navigate to `chrome://extensions` (or `edge://extensions`).
2. Enable **Developer mode** toggle in the top-right corner.
3. Click **Load unpacked** and select this directory (`/home/vaseline/Projects/vimium`).
4. Whenever you change extension files, click the **Reload (⟳)** icon on the Vimium extension card,
   then refresh your test browser tab.

### Loading in Firefox

1. Generate the Firefox-compatible manifest:
   ```bash
   ./make.js write-firefox-manifest
   ```
2. Navigate to `about:debugging#/runtime/this-firefox`.
3. Click **Load Temporary Add-on...** and select `manifest.json`.

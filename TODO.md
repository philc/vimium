# TODO

## Tab history — jump to last selected tab

**Status: already implemented, just not under this name.** This doc originally proposed
building a new per-window in-memory history stack, but that duplicates functionality that
already exists in this codebase:

- `background_scripts/tab_recency.js` (`TabRecency` class) tracks tab-activation order
  globally via `chrome.tabs.onActivated` / `chrome.windows.onFocusChanged`, persisted to
  `chrome.storage.session` (survives service-worker restarts — the original in-memory
  proposal below would not have).
- It's exposed as the `bgUtils.tabRecency` singleton (`background_scripts/bg_utils.js`).
- `visitPreviousTab` (`background_scripts/main.js`, bound to `^` via
  `background_scripts/commands.js`) already jumps back through this history, and supports
  a count prefix to cycle further back.

One real difference from the original proposal: `TabRecency` is global across all
windows, not scoped per-window. If per-window-only `^` navigation is ever wanted, that
would mean filtering `getTabsByRecency()` by `windowId` in `visitPreviousTab` — not
implemented, no current need for it.

`za`/`zA` (see below) now also build on `TabRecency` via a new
`bgUtils.getLastActiveTab({ windowId, excludeTabId, isValid })` helper, so this is the
shared mechanism going forward — don't add a second, competing history store.

## `za` / `zA` — collapse tab group(s) and jump to a sensible tab

**Status: implemented.**

- `za` (`collapseTabGroup`, `background_scripts/tab_groups.js`) collapses the current
  tab's group and jumps to the last-active tab outside that group (via
  `bgUtils.getLastActiveTab`), falling back to the previous index-proximity search, then
  to opening a new tab, if no candidate is found.
- `zA` (`collapseAllTabGroups`, same file) collapses every expanded group in the window,
  then jumps to the last-active *ungrouped* tab, with the same index-proximity → new-tab
  fallback chain.
- Tests: `tests/unit_tests/tab_groups_test.js`, `tests/unit_tests/bg_utils_test.js`.

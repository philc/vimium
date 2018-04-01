Vimium - The Hacker's Browser
=============================

[![Build Status](https://travis-ci.org/philc/vimium.svg?branch=master)](https://travis-ci.org/philc/vimium)

Vimium is a Chrome extension that provides keyboard-based navigation and control of the web in the spirit of
the Vim editor.

__Installation instructions:__

You can install the stable version of Vimium from the
[Chrome Extensions Gallery](https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb).

Please see
[CONTRIBUTING.md](CONTRIBUTING.md#installing-from-source)
for instructions on how you can install Vimium from source.

The Options page can be reached via a link on the help dialog (type `?`) or via the button next to Vimium on
the Chrome Extensions page (`chrome://extensions`).

Keyboard Bindings
-----------------

Modifier keys are specified as `<c-x>`, `<m-x>`, and `<a-x>` for ctrl+x, meta+x, and alt+x
respectively. For shift+x and ctrl-shift-x, just type `X` and `<c-X>`. See the next section for how to customize these bindings.

Once you have Vimium installed, you can see this list of key bindings at any time by typing `?`.

Navigating the current page:

    ?       show the help dialog for a list of all available keys
    h       scroll left
    j       scroll down
    k       scroll up
    l       scroll right
    gg      scroll to top of the page
    G       scroll to bottom of the page
    d       scroll down half a page
    u       scroll up half a page
    f       open a link in the current tab
    F       open a link in a new tab
    r       reload
    gs      view source
    i       enter insert mode -- all commands will be ignored until you hit Esc to exit
    yy      copy the current url to the clipboard
    yf      copy a link url to the clipboard
    gf      cycle forward to the next frame
    gF      focus the main/top frame

Navigating to new pages:

    o       Open URL, bookmark, or history entry
    O       Open URL, bookmark, history entry in a new tab
    b       Open bookmark
    B       Open bookmark in a new tab

Using find:

    /       enter find mode
              -- type your search query and hit enter to search, or Esc to cancel
    n       cycle forward to the next find match
    N       cycle backward to the previous find match

For advanced usage, see [regular expressions](https://github.com/philc/vimium/wiki/Find-Mode) on the wiki.

Navigating your history:

    H       go back in history
    L       go forward in history

Manipulating tabs:

    J, gT   go one tab left
    K, gt   go one tab right
    g0      go to the first tab
    g$      go to the last tab
    ^       visit the previously-visited tab
    t       create tab
    yt      duplicate current tab
    x       close current tab
    X       restore closed tab (i.e. unwind the 'x' command)
    T       search through your open tabs
    W       move current tab to new window
    <a-p>   pin/unpin current tab

Using marks:

    ma, mA  set local mark "a" (global mark "A")
    `a, `A  jump to local mark "a" (global mark "A")
    ``      jump back to the position before the previous jump
              -- that is, before the previous gg, G, n, N, / or `a

Additional advanced browsing commands:

    ]], [[  Follow the link labeled 'next' or '>' ('previous' or '<')
              - helpful for browsing paginated sites
    <a-f>   open multiple links in a new tab
    gi      focus the first (or n-th) text input box on the page
    gu      go up one level in the URL hierarchy
    gU      go up to root of the URL hierarchy
    ge      edit the current URL
    gE      edit the current URL and open in a new tab
    zH      scroll all the way left
    zL      scroll all the way right
    v       enter visual mode; use p/P to paste-and-go, use y to yank
    V       enter visual line mode

Vimium supports command repetition so, for example, hitting `5t` will open 5 tabs in rapid succession. `<Esc>` (or
`<c-[>`) will clear any partial commands in the queue and will also exit insert and find modes.

There are some advanced commands which aren't documented here; refer to the help dialog (type `?`) for a full
list.

Custom Key Mappings
-------------------

You may remap or unmap any of the default key bindings in the "Custom key mappings" on the options page.

Enter one of the following key mapping commands per line:

- `map key command`: Maps a key to a Vimium command. Overrides Chrome's default behavior (if any).
- `unmap key`: Unmaps a key and restores Chrome's default behavior (if any).
- `unmapAll`: Unmaps all bindings. This is useful if you want to completely wipe Vimium's defaults and start
  from scratch with your own setup.

Examples:

- `map <c-d> scrollPageDown` maps ctrl+d to scrolling the page down. Chrome's default behavior of bringing up
  a bookmark dialog is suppressed.
- `map r reload` maps the r key to reloading the page.
- `unmap <c-d>` removes any mapping for ctrl+d and restores Chrome's default behavior.
- `unmap r` removes any mapping for the r key.

Available Vimium commands can be found via the "Show available commands" link
near the key mapping box on the options page. The command name appears to the
right of the description in parenthesis.

You can add comments to key mappings by starting a line with `"` or `#`.

The following special keys are available for mapping:

- `<c-*>`, `<a-*>`, `<m-*>` for ctrl, alt, and meta (command on Mac) respectively with any key. Replace `*`
  with the key of choice.
- `<left>`, `<right>`, `<up>`, `<down>` for the arrow keys.
- `<f1>` through `<f12>` for the function keys.
- `<space>` for the space key.
- `<tab>`, `<enter>`, `<delete>`, `<backspace>`, `<insert>`, `<home>` and `<end>` for the corresponding non-printable keys (version 1.62 onwards).

Shifts are automatically detected so, for example, `<c-&>` corresponds to ctrl+shift+7 on an English keyboard.

More documentation
------------------
Many of the more advanced or involved features are documented on
[Vimium's GitHub wiki](https://github.com/philc/vimium/wiki). Also
see the [FAQ](https://github.com/philc/vimium/wiki/FAQ).

Contributing
------------
Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

Firefox Support
---------------

There is an *experimental* port of Vimium on Firefox [here](https://addons.mozilla.org/en-GB/firefox/addon/vimium-ff/).
This is very much experimental: most features work, although some bugs and issues remain.

PRs are welcome.

Release Notes
-------------

In `master` (not yet released)

- Custom search engines can now be `javascript:` URLs (eg., search the current [site](https://github.com/philc/vimium/issues/2956#issuecomment-366509915)).

1.63 (2018-02-16)

- The `reload` command now accepts a count prefix; so `999r` reloads all tabs (in the current window).
- Better detection of click listeners for link hints.
- Display version number in page popup.
- The Vomnibar is now loaded on demand (not preloaded).  This should fix some issues with the dev console.
- The `\I` control (case sensitivity) for find mode has been removed.  Find mode uses smartcase.
- Various bug fixes.
- 1.63.1 (Firefox only):
    - Fix [#2958](https://github.com/philc/vimium/issues/2958#issuecomment-366488659), link hints broken for `target="_blank"` links.
- 1.63.2 (Firefox only):
    - Fix [#2962](https://github.com/philc/vimium/issues/2962), find mode broken on Firefox Quantum.
- 1.63.3:
    - Fix [#2997](https://github.com/philc/vimium/issues/2997), Vimium's DOM injection breaks Google Pay site.

1.62 (2017-12-09)

- Backup and restore Vimium options (see the very bottom of the options page, below *Advanced Options*).
- It is now possible to map `<tab>`, `<enter>`, `<delete>`, `<insert>`, `<home>` and `<end>`.
- New command options for `createTab` to create new normal and incognito windows
  ([examples](https://github.com/philc/vimium/wiki/Tips-and-Tricks#creating-tabs-with-urls-and-windows)).
- Firefox only:
    - Fix copy and paste commands.
    - When upgrading, you will be asked to re-validate permissions.  The only
      new permission is "copy and paste to/from clipboard" (the
      `clipboardWrite` permission).  This is necessary to support copy/paste on
      Firefox.
- Various bug fixes.
- 1.62.1: Swap global and local marks (1.62.1).
  In a browser, some people find global marks more useful than local marks.
  Example:

```
map X Marks.activateCreateMode swap
map Y Marks.activateGotoMode swap
```

- Other minor versions:
    - 1.62.2: Fixes [#2868](https://github.com/philc/vimium/issues/2868) (`createTab` with multiple URLs).
    - 1.62.4: Fixes bug affecting the enabled state, and really fix `createTab`.

1.61 (2017-10-27)

- For *filtered hints*, you can now use alphabetical hint characters
  instead of digits; use `<Shift>` for hint characters.
- With `map R reload hard`, the reload command now asks Chrome to bypass its cache.
- You can now map `<c-[>` to a command (in which case it will not be treated as `Escape`).
- Various bug fixes, particularly for Firefox.
- Minor versions:
    - 1.61.1: Fix `map R reload hard`.

1.60 (2017-09-14)

- Features:
    - There's a new (advanced) option to ignore the keyboard layout; this can
      be helpful for users of non-Latin keyboards.
    - Firefox support.  This is a work in progress; please report any issues
      [here](https://github.com/philc/vimium/issues?q=is%3Aopen+sort%3Aupdated-desc);
      see the [add
      on](https://addons.mozilla.org/en-GB/firefox/addon/vimium-ff/).

- Bug fixes:
    - Fixed issue affecting hint placement when the display is zoomed.
    - Fixed search completion for Firefox (released as 1.59.1, Firefox only).

- Minor versions:
    - 1.60.1: fix [#2642](https://github.com/philc/vimium/issues/2642).
    - 1.60.2: revert previous fix for HiDPI screens.  This was breaking link-hint positioning for some users.
    - 1.60.3: [fix](https://github.com/philc/vimium/pull/2649) link-hint positioning.
    - 1.60.4: [fix](https://github.com/philc/vimium/pull/2602) hints opening in new tab (Firefox only).

1.59 (2017-04-07)

- Features:
    - Some commands now work on PDF tabs (`J`, `K`, `o`, `b`, etc.). Scrolling and other content-related commands still do not work.

1.58 (2017-03-08)

- Features:
    - The `createTab` command can now open specific URLs (e.g, `map X createTab http://www.bbc.com/news`).
    - With pass keys defined for a site (such as GMail), you can now use Vimium's bindings again with, for example, `map \ passNextKey normal`;
      this reactivates normal mode temporarily, but *without any pass keys*.
    - You can now map multi-modifier keys, for example: `<c-a-X>`.
    - Vimium can now do simple key mapping in some modes; see
      [here](https://github.com/philc/vimium/wiki/Tips-and-Tricks#key-mapping).
      This can be helpful with some non-English keyboards (and can also be used
      to remap `Escape`).
    - For *Custom key mappings* on the options page, lines which end with `\` are now continued on the following line.
- Process:
    - In order to provide faster bug fixes, we may in future push new releases without the noisy notification.

- Post-release minor fixes:
    - 1.58.1 (2017-03-09) fix bug in `LinkHints.activateModeWithQueue` (#2445).
    - 1.58.2 (2017-03-19) fix key handling bug (#2453).

1.57 (2016-10-01)

- New commands:
    - `toggleMuteTab` - mute or unmute the current tab (default binding
      `<a-m>`), see also [advanced usage](https://github.com/philc/vimium/wiki/Tips-and-Tricks#muting-tabs).
- Other new features:
    - You can now map `<backspace>` to a Vimium command (e.g. `map <backspace> goBack`).
    - For link hints, when one hint marker is covered by another, `<Space>` now
      rotates the stacking order.  If you use filtered hints, you'll need to
      use a modifier (e.g. `<c-Space>`).
- Changes:
    - Global marks now search for an existing matching tab by prefix (rather than exact match).
      This allows global marks to be used as quick bookmarks on sites (like Facebook, Gmail, etc)
      where the URL changes as you navigate around.
- Bug fixes:
    - `/i` can no longer hang Vimium while the page is loading.
    - `<c-a-[>` is no longer handled (incorrectly) as `Escape`.  This also affects `<Alt-Gr-[>`.
    - If `goX` is mapped, then `go` no longer launches the vomnibar.  This only affects three-key (or longer) bindings.

1.56 (2016-06-11)

- Vimium now works around a Chromium bug affecting users with non-standard keyboard layouts (see #2147).
- Fixed a bug preventing visual line mode (`V`) from working.

1.55 (2016-05-26)

- New commands:
    - `visitPreviousTab` - visit the previous tab (by recency) with `^`, or the tab before that with `2^`.
    - `passNextKey` - pass the next key to the page. For example, using `map <c-]> passNextKey`, you can close
      Facebook's messenger popups with `<c-]><Esc>`.
- Link hints:
    - Now work across all frames in the tab.
    - Now select frames and scrollable elements.
    - Now accept a count prefix; `3F` opens three new background tabs, `999F` opens many tabs.
    - For filtered link hints, a new option on the settings page requires you to press `Enter` to activate a
      link; this prevents unintentionally triggering Vimium commands with trailing keystrokes.
- Miscellaneous:
    - `gg` now accepts a `count` prefix.
    - `W` now accepts a count prefix; `3W` moves three tabs to a new window.
    - With smooth scrolling, `2j`-and-hold now gives a faster scroll than `j`-and-hold.
    - You can now bind keys to a command with a defined count prefix; for example, `map d scrollDown count=4`.
    - You can now bind three-key (or longer) sequences; for example, `map abc enterInsertMode`.
    - `c-y` and `c-e` now scroll in visual mode.
    - The Vimium help dialog has been re-styled.
- Bug fixes:
    - `<c-a-[>` is no longer treated as escape.
    - Fix icon display and memory leak due to a regression in recent Chrome versions (49+).
- For web-devs only:
    - When disabled on a tab, Vimium no longer pollutes the dev console with network requests.

1.54 (2016-01-30)

- Fix occasional endless scrolling (#1911).

1.53 (2015-09-25)

- Vimium now works on the new-tab page for Chrome 47.
- `g0` and `g$` now accept count prefixes; so `2g0` selects the second tab, and so on.
- Bug fixes:
    - Fix `moveTabLeft` and `moveTabRight` for pinned tabs (#1814 and #1815).

1.52 (2015-09-09)

- Search completion for selected custom search engines
  (details on the [wiki](https://github.com/philc/vimium/wiki/Search-Completion)).
- Use `Tab` on an empty Vomnibar to repeat or edit recent queries
  (details on the [wiki](https://github.com/philc/vimium/wiki/Tips-and-Tricks#repeat-recent-vomnibar-queries)).
- Marks:
    - Use <tt>\`\`</tt> to jump back to the previous position after jump-like movements: <br/>
        (`gg`, `G`, `n`, `N`, `/` and local mark movements).
    - Global marks are now persistent and synced.
- For numeric link hints, you can now use `Tab` and `Enter` to select hints, and hints are ordered by the best
  match.
- The Find Mode text entry box now supports editing, pasting, and better handles non-latin characters.
- Vimium now works on XML pages.
- Bug fixes.

1.51 (2015-05-02)

- Bug [fixes](https://github.com/philc/vimium/pulls?utf8=%E2%9C%93&q=is%3Apr+sort%3Aupdated-desc+is%3Aclosed+merged%3A%3E%3D2015-04-26+merged%3A%3C2015-05-02+state%3Amerged).

1.50 (2015-04-26)

- Visual mode (in beta): use `v` and then vim-like keystrokes to select text on the page. Use `y` to yank or
  `p` and `P` to search with your default search engine.. Please provide feedback on Github.
- Added the option to prevent pages from stealing focus from Vimium when loaded.
- Many bugfixes for custom search engines, and search engines can now have a description.
- Better support for frames: key exclusion rules are much improved and work within frames; the Vomnibar is
  always activated in the main frame; and a new command (`gF`) focuses the main frame.
- Find mode now has history. Use the up arrow to select previous searches.
- Ctrl and Shift when using link hints changes the tab in which links are opened in (reinstated feature).
- Focus input (`gi`) remembers previously-visited inputs.
- Bug fixes.

1.49 (2014-12-16)

- An option to toggle smooth scrolling.
- Make Vimium work on older versions of Chrome.

1.46, 1.47, 1.48 (2014-12-15)

- Site-specific excluded keys: you can disable some Vimium key bindings on sites like gmail.com, so you can use the key bindings provided by the site itself.
- Smooth scrolling.
- The Vomnibar now orders tabs by recency. Use this to quickly switch between your most recently-used tabs.
- New commands: "close tabs to the left", "close tabs to the right", "close all other tabs".
- Usability improvements.
- Bug fixes.

1.45 (2014-07-20)

- Vimium's settings are now synced across computers.
- New commands: "open link in new tab and focus", "move tab left", "move tab right", "pin/unpin tab".
- Vomnibar can now use [search engine shortcuts](https://github.com/philc/vimium/wiki/Search-Engines), similar to Chrome's Omnibar.
- Due to significant ranking improvements, Vomnibar's search results are now even more helpful.
- When reopening a closed tab, its history is now preserved.
- Bug fixes.

1.44 (2013-11-06)

- Add support for recent versions of Chromium.
- Bug fixes.

1.43 (2013-05-18)

- Relevancy improvements to the Vomnibar's domain & history search.
- Added `gU`, which goes to the root of the current URL.
- Added `yt`, which duplicates the current tab.
- Added `W`, which moves the current tab to a new window.
- Added marks for saving and jumping to sections of a page. `mX` to set a mark and `` `X`` to return to it.
- Added "LinkHints.activateModeToOpenIncognito", currently an advanced, unbound command.
- Disallowed repeat tab closings, since this causes trouble for many people.
- Update our Chrome APIs so Vimium works on Chrome 28+.
- Bug fixes.

1.42 (2012-11-03)

- Bug fixes.

1.41 (2012-10-27)

- Bug fixes.

1.40 (2012-10-27)

- Bug fixes.
- Added options for search engines and regex find.
- Pressing unmapped keys in hints mode now deactivates the mode.

1.39 (2012-09-09)

- Bug fixes.

1.38 (2012-09-08)

- `O` now opens Vomnibar results in a new tab. `B` does the same for bookmarks only.
- Add a browser icon to quickly add sites to Vimium's exclude list.
- Restyle options page.
- `gi` now launches a new mode that allows the user to tab through the input elements on the page.
- Bug fixes.

1.37 (2012-07-07)

- Select the first result by default in Vomnibar tab and bookmark modes.

1.36 (2012-07-07)

- `b` brings up a bookmark-only Vomnibar.
- Better support for some bookmarklets.

1.35 (2012-07-05)

- Bug fixes.

1.34 (2012-07-03)

- A bug fix for bookmarklets in Vomnibar.

1.33 (2012-07-02)

- A Vomnibar, which allows you to open sites from history, bookmarks, and tabs using Vimium's UI. Type `o` to try it.

1.32 (2012-03-05)

- More tweaks to the next / previous link-detection algorithm.
- Minor bug fixes.

1.31 (2012-02-28)

- Improve style of link hints, and use fewer characters for hints.
- Add an option to hide the heads up display (HUD). Notably, the HUD obscures Facebook Chat's textbox.
- Detection and following of next / previous links has been improved.
- Addition of `g0` and `g$` commands, for switching tabs.
- Addition of `p`/`P` commands for URL pasting.
- A new find mode which optionally supports case sensitivity and regular expressions.
- Bug fixes.

1.30 (2011-12-04)

- Support for image maps in link hints.
- Counts now work with forward & backward navigation.
- `Tab` & `shift-tab` to navigate bookmarks dialog.
- An alternate link hints mode: type the title of a link to select it. You can enable it in Vimium's Advanced Preferences.
- Bug fixes.

1.29 (2012-07-30)

- `yf` to copy a link hint url to the clipboard.
- Scatter link hints to prevent clustering on dense sites.
- Don't show insert mode notification unless you specifically hit `i`.
- Remove zooming functionality now that Chrome does it all natively.

1.28 (2011-06-29)

- Support for opening bookmarks (`b` and `B`).
- Support for contenteditable text boxes.
- Speed improvements and bug fixes.

1.27 (2011-03-24)

- Improvements and bug fixes.

1.26 (2011-02-17)

- `<c-d>`, `<c-f>` and related are no longer bound by default. You can rebind them on the options page.
- Faster link hinting.

1.22, 1.23, 1.24, 1.25 (2011-02-10)

-  Some sites are now excluded by default.
-  View source (`gs`) now opens in a new tab.
-  Support for browsing paginated sites using `]]` and `[[` to go forward and backward respectively.
-  Many of the less-used commands are now marked as "advanced" and hidden in the help dialog by default, so
   that the core command set is more focused and approachable.
-  Improvements to link hinting.
-  Bug fixes.

1.21 (2010-10-24)

-  Critical bug fix for an excluded URLs regression due to frame support.

1.20 (2010-10-24)

-  In link hints mode, holding down the shift key will now toggle between opening in the current tab and
   opening in a new tab.
-  Two new commands (`zH` and `zL`) to scroll to the left and right edges of the page.
-  A new command (`gi`) to focus the first (or n-th) visible text input.
-  A new command (`<a-f>`) to open up multiple links at a time in new tabs.
-  Frame support.
-  More robust support for non-US keyboard layouts.
-  Numerous bug fixes.

1.19 (2010-06-29)

-  A critical bug fix for development channel Chromium.
-  Vimium icons for the Chrome extensions panel and other places.

1.18 (2010-06-22)

-  Vimium now runs on pages with file:/// and ftp:///
-  The Options page is now linked from the Help dialog.
-  Arrow keys and function keys can now be mapped using &lt;left&gt;, &lt;right&gt;, &lt;up&gt;, &lt;down&gt;,
   &lt;f1&gt;, &lt;f2&gt;, etc. in the mappings interface.
-  There is a new command `goUp` (mapped to `gu` by default) that will go up one level in the URL hierarchy.
   For example: from https://vimium.github.io/foo/bar to https://vimium.github.io/foo. At the moment, `goUp`
does not support command repetition.
-  Bug fixes and optimizations.

1.17 (2010-04-18)

-  `u` now restores tabs that were closed by the mouse or with native shortcuts. Tabs are also restored in
   their prior position.
-  New `unmapAll` command in the key mappings interface to remove all default mappings.
-  Link hints are now faster and more reliable.
-  Bug fixes.

1.16 (2010-03-09)

-  Add support for configurable key mappings under Advanced Options.
-  A help dialog which shows all currently bound keyboard shortcuts. Type `?` to see it.
-  Bug fixes related to key stroke handling.

1.15 (2010-01-31)

-  Make the CSS used by the link hints configurable. It's under Advanced Options.
-  Add a notification linking to the changelog when Vimium is updated in the background.
-  Link-hinting performance improvements and bug fixes.
-  `Ctrl+D` and `Ctrl+U` now scroll by 1/2 page instead of a fixed amount, to mirror Vim's behavior.

1.14 (2010-01-21)

-  Fixed a bug introduced in 1.13 that prevented excluded URLs from being saved.

1.13 (2010-01-21)

- `<c-f>` and `<c-b>` are now mapped to scroll a full page up or down respectively.
-  Bug fixes related to entering insert mode when the page first loads, and when focusing Flash embeds.
-  Added command listing to the Options page for easy reference.
-  `J` & `K` have reversed for tab switching: `J` goes left and `K` goes right.
-  `<c-[>` is now equivalent to `Esc`, to match the behavior of VIM.
-  `<c-e>` and `<c-y>` are now mapped to scroll down and up respectively.
-  The characters used for link hints are now configurable under Advanced Options.

1.11, 1.12 (2010-01-08)

-  Commands `gt` & `gT` to move to the next & previous tab.
-  Command `yy` to yank (copy) the current tab's url to the clipboard.
-  Better Linux support.
-  Fix for `Shift+F` link hints.
-  `Esc` now clears the keyQueue. So, for example, hitting `g`, `Esc`, `g` will no longer scroll the page.

1.1 (2010-01-03)

-  A nicer looking settings page.
-  An exclusion list that allows you to define URL patterns for which Vimium will be disabled (e.g.
   http\*://mail.google.com/\*).
-  Vimium-interpreted keystrokes are no longer sent to the page.
-  Better Windows support.
-  Various miscellaneous bug fixes and UI improvements.

License
-------
Copyright (c) Phil Crosby, Ilya Sukhar. See MIT-LICENSE.txt for details.

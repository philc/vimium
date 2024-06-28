2.1.2 (2024-04-03)

- Better fix for Vomnibar doesn't always list tabs by recency.
  ([#4368](https://github.com/philc/vimium/issues/4368))
- Add a workaround to make link hints work on Github Enterprise.
  ([#4446](https://github.com/philc/vimium/issues/4446))
- Fix position=end is ignored in createTab command
  ([#4450](https://github.com/philc/vimium/issues/4450))

2.1.1 (2024-03-29)

- Fix exclusion rule popup not working. ([#4447](https://github.com/philc/vimium/issues/4447))

2.1.0 (2024-03-27)

- Fix Vomnibar doesn't always list tabs by recency.
  ([#4368](https://github.com/philc/vimium/issues/4368))
- Better domain detection in the Vomnibar ([#3268](https://github.com/philc/vimium/issues/3268))
- Exclude keys based on the top frame URL, not a subframe's URL. This fixes many cases where the
  excluded keys feature didn't seem to work. ([#4402](https://github.com/philc/vimium/issues/4402))
- After selecting a link, if ESC is pressed, mouse out of the link. With this, Wikipedia's and
  Github's link preview popups can be dismissed after following a link.
  ([#3073](https://github.com/philc/vimium/issues/3073))
- Fix link hints do not appear for links inside of github's popups. This fix is available on Chrome
  114+, and soon Firefox. ([#4408](https://github.com/philc/vimium/issues/4408))

2.0.5, 2.0.6 (2023-11-06)

- Fix bug where "esc" wouldn't unfocus a textarea like it should.
  ([#4336](https://github.com/philc/vimium/issues/4336))
- Fix passNextKey command.

2.0.4 (2023-10-19)

- Bug fixes: ([#4340](https://github.com/philc/vimium/issues/4340)),
  ([#4341](https://github.com/philc/vimium/issues/4341)),
  ([#4342](https://github.com/philc/vimium/issues/4342)).

2.0.2, 2.0.3 (2023-10-11)

- Fix Vomnibar tab search doesn't get pre-populated with recently visited tabs.
  ([#4326](https://github.com/philc/vimium/issues/4326))
- Fix bookmarklets not working when opened from the Vomnibar. This is a partial fix; a full fix is
  waiting on a new extensions API. See [#4329](https://github.com/philc/vimium/issues/4329) for
  discussion.

2.0.1 (2023-10-04)

- Fix exception when migrating some pre-v2.0 settings. ([#4323](https://github.com/philc/vimium/issues/4323))

2.0.0 (2023-09-28 -- partially rolled out to users on the Chrome store)

- Support manifest v3, as now required by Chrome. This involved a partial rewrite and many changes.
  Please report any new issues [here](https://github.com/philc/vimium/issues).
- The storage format for Vimium's options has changed in v2.x. That means an options backup from
  Vimium v2.x cannot be loaded on Vimium v1.x installations.
- Revamp the action bar UI, which configures which keys Vimium ignores on a particular site.
- Improve Vimium's options UI.
- Show link hints for image maps. ([#3493](https://github.com/philc/vimium/issues/3493))
- Remove the use of window.unload handlers, in preparation for Chrome's bfcache.
  ([#4265](https://github.com/philc/vimium/issues/4265))
- Allow find mode to work when using only private windows.
  ([#3614](https://github.com/philc/vimium/issues/3614))
- Add a count option to closeTabsOnLeft and closeTabsOnRight commands, to allow binding a key to
  "close just 1 tab on the left/right" rather than closing all tabs, as is the default. E.g. `map cl
  closeTabsOnLeft count=1`. ([#4296](https://github.com/philc/vimium/pull/4296))
- Add search completions for Brave Search. ([#3851](https://github.com/philc/vimium/pull/3851))
- Make regular expressions in find mode work again; other find mode improvements.
  ([#4261](https://github.com/philc/vimium/issues/4261))
- Bug fixes. ([#3944](https://github.com/philc/vimium/pull/3944),
[#3752](https://github.com/philc/vimium/pull/3752),
[#3675](https://github.com/philc/vimium/pull/3675))

1.67.7 (2023-07-12)

- Fix an issue where focusing the google search box puts the cursor at the start, rather than end,
  of the search box. ([#4247](https://github.com/philc/vimium/issues/4247))

1.67.6 (2022-12-19)

- Fix a spurious issue preventing approval on the Mozilla addons site
  ([#4195](https://github.com/philc/vimium/issues/4195))

1.67.5 (2022-12-17)

- For Firefox only, add back the clipboard read and write permissions. This fixes the Vimium
  commands which use the clipboard in Firefox ([#4186](https://github.com/philc/vimium/pull/4186))

1.67.4 (2022-12-01)

- Remove clipboard read/write permissions. We no longer need them since 1.67.2 (see #4120).
- Fix Vimium's dark mode styling, take 2 (see [#4156](https://github.com/philc/vimium/issues/4156),
  [#4159](https://github.com/philc/vimium/pull/4159))

1.67.3 (2022-10-29)

- Fix copy-to-clipboard issue ([#4147](https://github.com/philc/vimium/issues/4147)) in visual mode.
- Fix Vimium's dark mode styling in latest Firefox.
  ([#4148](https://github.com/philc/vimium/issues/4148))

1.67.2 (2022-10-17)

- In Firefox, remove use of deprecated InstallTrigger, which was issuing a console warning
  ([#4033](https://github.com/philc/vimium/issues/4033))
- Fix the Vimium toolbar icon to accurately reflect whether keys are excluded
  ([#4118](https://github.com/philc/vimium/pull/4118))
- Fix usage of deprecated clipboard APIs, which affected commands using copy and paste
  ([#4120](https://github.com/philc/vimium/issues/4120))
- Fix bug preventing going into caret mode ([#3877](https://github.com/philc/vimium/pull/3877))

1.67.1 (2022-01-19)

- In Firefox 96+, make link hints open one tab, not two
  ([#3985](https://github.com/philc/vimium/pull/3985))

1.67 (2021-07-09)

- Dark mode: Vimium's UI (URL bar, help dialog, option page, etc.) are dark if the browser is
  configured for dark mode. Vimium's dark mode is also compatible when using the popular
  [DarkReader extension](https://github.com/darkreader/darkreader).
- Convert the code base from Coffeescript to Javascript, to simplify the dev experience and allow
  more developers to work on Vimium.
- Make search mode work in newer versions of Firefox (#3801)
- Make buttons on the Vimium options page work again in newer versions of Firefox (#3624)
- Allow Vimium to work in LibreWolf (a Firefox fork)
- Fixes to visual mode (#3568, #3779)

1.66 (2020-03-02)

- Show tabs in the Vomnibar bar search results ('o')
  ([#2656](https://github.com/philc/vimium/pull/2656))
- Add commands to hover or focus a link ([#3097](https://github.com/philc/vimium/pull/3097)) (see
  [wiki)](https://github.com/philc/vimium/wiki/Tips-and-Tricks#hovering-over-links-using-linkhints)
- Allow shift as a modifier for keybindings (e.g. `<s-left>`)
  ([#2388](https://github.com/philc/vimium/pull/2388))
- Fix some issues with link hints [(#3499](https://github.com/philc/vimium/pull/3499),
  [#3505](https://github.com/philc/vimium/pull/3505),
  [#3509](https://github.com/philc/vimium/pull/3509))
- Other fixes.

1.65.2 (2020-02-10)

- No code changes; trying to debug a permissions issue as shown in the chrome store
  ([#3489](https://github.com/philc/vimium/issues/3489)).

1.65.1 (2020-02-09)

- Fix an issue with the HUD preventing some link hints from being shown
  ([#3486](https://github.com/philc/vimium/issues/3486)).

1.65 (2020-02-08)

- Many fixes for Firefox ([#3483](https://github.com/philc/vimium/pull/3483),
  [#2893](https://github.com/philc/vimium/issues/2893),
  [#3106](https://github.com/philc/vimium/issues/3106),
  [#3409](https://github.com/philc/vimium/pull/3409),
  [#3288](https://github.com/philc/vimium/pull/3288))
- Fix javascript bookmarks, broken by Chrome 71+
  [(#3473)](https://github.com/philc/vimium/pull/3437)
- Improved link hints: show hints on sites with shadow DOM
  [(#3406)](https://github.com/philc/vimium/pull/3406), don't show hints for obstructed/invisible
  links ([#2251](https://github.com/philc/vimium/pull/2251))
- Fix scrolling on Reddit.com ([#3327](https://github.com/philc/vimium/pull/3327))
- Show favicons when using the tab switcher ([#2878](https://github.com/philc/vimium/pull/2878))
- The createTab command can now take arguments (start, end, before, after)
  ([#2895](https://github.com/philc/vimium/pull/2895))
- When using the Vomnibar, you can manually edit the suggested URL by typing ctrl-enter
  [(#2464)](https://github.com/philc/vimium/pull/2914)
- Other fixes

1.64.6 (2019-05-12)

- Fix the find mode, and copying the page's URL to the clipboard, which were broken by Chrome 74+.
  ([#3260](https://github.com/philc/vimium/issues/3260))

1.64.5 (2019-02-16)

- Fix error in Chrome Store distribution.

1.64.4 (2019-02-16)

- Fix [Vomnibar focus issue](https://github.com/philc/vimium/issues/3242).

1.64.3 (2018-12-26)

- When yanking email addresses with `yf`, Vimium now strips the leading `mailto:`.
- For custom search engines, if you use `%S` (instead of `%s`), then your search terms are not URI
  encoded.
- Bug fixes (including horizontal scrolling broken).

1.64.2 (2018-12-16)

- Better scrolling on new Reddit ~~and GMail~~.

1.64 (2018-08-30)

- Custom search engines can now be `javascript:` URLs (eg., search the current
  [site](https://github.com/philc/vimium/issues/2956#issuecomment-366509915)).
- You can now using local marks to mark a hash/anchor. This is particularly useful for marking
  labels on GMail.
- For filtered hints, you can now start typing the link text before the hints have been generated.
- On Twitter, expanded tweets are now scrollable.
- Fix bug whereby `<Enter>` wasn't recognised in the Vomnibar in some circumstances.
- Various minor bug fixes.

1.63 (2018-02-16)

- The `reload` command now accepts a count prefix; so `999r` reloads all tabs (in the current
  window).
- Better detection of click listeners for link hints.
- Display version number in page popup.
- The Vomnibar is now loaded on demand (not preloaded). This should fix some issues with the dev
  console.
- The `\I` control (case sensitivity) for find mode has been removed. Find mode uses smartcase.
- Various bug fixes.
- 1.63.1 (Firefox only):
  - Fix [#2958](https://github.com/philc/vimium/issues/2958#issuecomment-366488659), link hints
    broken for `target="_blank"` links.
- 1.63.2 (Firefox only):
  - Fix [#2962](https://github.com/philc/vimium/issues/2962), find mode broken on Firefox Quantum.
- 1.63.3:
  - Fix [#2997](https://github.com/philc/vimium/issues/2997), Vimium's DOM injection breaks Google
    Pay site.

1.62 (2017-12-09)

- Backup and restore Vimium options (see the very bottom of the options page, below _Advanced
  Options_).
- It is now possible to map `<tab>`, `<enter>`, `<delete>`, `<insert>`, `<home>` and `<end>`.
- New command options for `createTab` to create new normal and incognito windows
  ([examples](https://github.com/philc/vimium/wiki/Tips-and-Tricks#creating-tabs-with-urls-and-windows)).
- Firefox only:
  - Fix copy and paste commands.
  - When upgrading, you will be asked to re-validate permissions. The only new permission is "copy
    and paste to/from clipboard" (the `clipboardWrite` permission). This is necessary to support
    copy/paste on Firefox.
- Various bug fixes.
- 1.62.1: Swap global and local marks (1.62.1). In a browser, some people find global marks more
  useful than local marks. Example:

```
map X Marks.activateCreateMode swap
map Y Marks.activateGotoMode swap
```

- Other minor versions:
  - 1.62.2: Fixes [#2868](https://github.com/philc/vimium/issues/2868) (`createTab` with multiple
    URLs).
  - 1.62.4: Fixes bug affecting the enabled state, and really fix `createTab`.

1.61 (2017-10-27)

- For _filtered hints_, you can now use alphabetical hint characters instead of digits; use
  `<Shift>` for hint characters.
- With `map R reload hard`, the reload command now asks Chrome to bypass its cache.
- You can now map `<c-[>` to a command (in which case it will not be treated as `Escape`).
- Various bug fixes, particularly for Firefox.
- Minor versions:
  - 1.61.1: Fix `map R reload hard`.

1.60 (2017-09-14)

- Features:
  - There's a new (advanced) option to ignore the keyboard layout; this can be helpful for users of
    non-Latin keyboards.
  - Firefox support. This is a work in progress; please report any issues
    [here](https://github.com/philc/vimium/issues?q=is%3Aopen+sort%3Aupdated-desc); see the
    [add on](https://addons.mozilla.org/en-GB/firefox/addon/vimium-ff/).

- Bug fixes:
  - Fixed issue affecting hint placement when the display is zoomed.
  - Fixed search completion for Firefox (released as 1.59.1, Firefox only).

- Minor versions:
  - 1.60.1: fix [#2642](https://github.com/philc/vimium/issues/2642).
  - 1.60.2: revert previous fix for HiDPI screens. This was breaking link-hint positioning for some
    users.
  - 1.60.3: [fix](https://github.com/philc/vimium/pull/2649) link-hint positioning.
  - 1.60.4: [fix](https://github.com/philc/vimium/pull/2602) hints opening in new tab (Firefox
    only).

1.59 (2017-04-07)

- Features:
  - Some commands now work on PDF tabs (`J`, `K`, `o`, `b`, etc.). Scrolling and other
    content-related commands still do not work.

1.58 (2017-03-08)

- Features:
  - The `createTab` command can now open specific URLs (e.g,
    `map X createTab http://www.bbc.com/news`).
  - With pass keys defined for a site (such as GMail), you can now use Vimium's bindings again with,
    for example, `map \ passNextKey normal`; this reactivates normal mode temporarily, but _without
    any pass keys_.
  - You can now map multi-modifier keys, for example: `<c-a-X>`.
  - Vimium can now do simple key mapping in some modes; see
    [here](https://github.com/philc/vimium/wiki/Tips-and-Tricks#key-mapping). This can be helpful
    with some non-English keyboards (and can also be used to remap `Escape`).
  - For _Custom key mappings_ on the options page, lines which end with `\` are now continued on the
    following line.
- Process:
  - In order to provide faster bug fixes, we may in future push new releases without the noisy
    notification.

- Post-release minor fixes:
  - 1.58.1 (2017-03-09) fix bug in `LinkHints.activateModeWithQueue` (#2445).
  - 1.58.2 (2017-03-19) fix key handling bug (#2453).

1.57 (2016-10-01)

- New commands:
  - `toggleMuteTab` - mute or unmute the current tab (default binding `<a-m>`), see also
    [advanced usage](https://github.com/philc/vimium/wiki/Tips-and-Tricks#muting-tabs).
- Other new features:
  - You can now map `<backspace>` to a Vimium command (e.g. `map <backspace> goBack`).
  - For link hints, when one hint marker is covered by another, `<Space>` now rotates the stacking
    order. If you use filtered hints, you'll need to use a modifier (e.g. `<c-Space>`).
- Changes:
  - Global marks now search for an existing matching tab by prefix (rather than exact match). This
    allows global marks to be used as quick bookmarks on sites (like Facebook, Gmail, etc) where the
    URL changes as you navigate around.
- Bug fixes:
  - `/i` can no longer hang Vimium while the page is loading.
  - `<c-a-[>` is no longer handled (incorrectly) as `Escape`. This also affects `<Alt-Gr-[>`.
  - If `goX` is mapped, then `go` no longer launches the vomnibar. This only affects three-key (or
    longer) bindings.

1.56 (2016-06-11)

- Vimium now works around a Chromium bug affecting users with non-standard keyboard layouts (see
  #2147).
- Fixed a bug preventing visual line mode (`V`) from working.

1.55 (2016-05-26)

- New commands:
  - `visitPreviousTab` - visit the previous tab (by recency) with `^`, or the tab before that with
    `2^`.
  - `passNextKey` - pass the next key to the page. For example, using `map <c-]> passNextKey`, you
    can close Facebook's messenger popups with `<c-]><Esc>`.
- Link hints:
  - Now work across all frames in the tab.
  - Now select frames and scrollable elements.
  - Now accept a count prefix; `3F` opens three new background tabs, `999F` opens many tabs.
  - For filtered link hints, a new option on the settings page requires you to press `Enter` to
    activate a link; this prevents unintentionally triggering Vimium commands with trailing
    keystrokes.
- Miscellaneous:
  - `gg` now accepts a `count` prefix.
  - `W` now accepts a count prefix; `3W` moves three tabs to a new window.
  - With smooth scrolling, `2j`-and-hold now gives a faster scroll than `j`-and-hold.
  - You can now bind keys to a command with a defined count prefix; for example,
    `map d scrollDown count=4`.
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

- Search completion for selected custom search engines (details on the
  [wiki](https://github.com/philc/vimium/wiki/Search-Completion)).
- Use `Tab` on an empty Vomnibar to repeat or edit recent queries (details on the
  [wiki](https://github.com/philc/vimium/wiki/Tips-and-Tricks#repeat-recent-vomnibar-queries)).
- Marks:
  - Use <tt>\`\`</tt> to jump back to the previous position after jump-like movements: <br/> (`gg`,
    `G`, `n`, `N`, `/` and local mark movements).
  - Global marks are now persistent and synced.
- For numeric link hints, you can now use `Tab` and `Enter` to select hints, and hints are ordered
  by the best match.
- The Find Mode text entry box now supports editing, pasting, and better handles non-latin
  characters.
- Vimium now works on XML pages.
- Bug fixes.

1.51 (2015-05-02)

- Bug
  [fixes](https://github.com/philc/vimium/pulls?utf8=%E2%9C%93&q=is%3Apr+sort%3Aupdated-desc+is%3Aclosed+merged%3A%3E%3D2015-04-26+merged%3A%3C2015-05-02+state%3Amerged).

1.50 (2015-04-26)

- Visual mode (in beta): use `v` and then vim-like keystrokes to select text on the page. Use `y` to
  yank or `p` and `P` to search with your default search engine.. Please provide feedback on Github.
- Added the option to prevent pages from stealing focus from Vimium when loaded.
- Many bugfixes for custom search engines, and search engines can now have a description.
- Better support for frames: key exclusion rules are much improved and work within frames; the
  Vomnibar is always activated in the main frame; and a new command (`gF`) focuses the main frame.
- Find mode now has history. Use the up arrow to select previous searches.
- Ctrl and Shift when using link hints changes the tab in which links are opened in (reinstated
  feature).
- Focus input (`gi`) remembers previously-visited inputs.
- Bug fixes.

1.49 (2014-12-16)

- An option to toggle smooth scrolling.
- Make Vimium work on older versions of Chrome.

1.46, 1.47, 1.48 (2014-12-15)

- Site-specific excluded keys: you can disable some Vimium key bindings on sites like gmail.com, so
  you can use the key bindings provided by the site itself.
- Smooth scrolling.
- The Vomnibar now orders tabs by recency. Use this to quickly switch between your most
  recently-used tabs.
- New commands: "close tabs to the left", "close tabs to the right", "close all other tabs".
- Usability improvements.
- Bug fixes.

1.45 (2014-07-20)

- Vimium's settings are now synced across computers.
- New commands: "open link in new tab and focus", "move tab left", "move tab right", "pin/unpin
  tab".
- Vomnibar can now use
  [search engine shortcuts](https://github.com/philc/vimium/wiki/Search-Engines), similar to
  Chrome's Omnibar.
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
- Added marks for saving and jumping to sections of a page. `mX` to set a mark and `` `X `` to
  return to it.
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

- A Vomnibar, which allows you to open sites from history, bookmarks, and tabs using Vimium's UI.
  Type `o` to try it.

1.32 (2012-03-05)

- More tweaks to the next / previous link-detection algorithm.
- Minor bug fixes.

1.31 (2012-02-28)

- Improve style of link hints, and use fewer characters for hints.
- Add an option to hide the heads up display (HUD). Notably, the HUD obscures Facebook Chat's
  textbox.
- Detection and following of next / previous links has been improved.
- Addition of `g0` and `g$` commands, for switching tabs.
- Addition of `p`/`P` commands for URL pasting.
- A new find mode which optionally supports case sensitivity and regular expressions.
- Bug fixes.

1.30 (2011-12-04)

- Support for image maps in link hints.
- Counts now work with forward & backward navigation.
- `Tab` & `shift-tab` to navigate bookmarks dialog.
- An alternate link hints mode: type the title of a link to select it. You can enable it in Vimium's
  Advanced Preferences.
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

- `<c-d>`, `<c-f>` and related are no longer bound by default. You can rebind them on the options
  page.
- Faster link hinting.

1.22, 1.23, 1.24, 1.25 (2011-02-10)

- Some sites are now excluded by default.
- View source (`gs`) now opens in a new tab.
- Support for browsing paginated sites using `]]` and `[[` to go forward and backward respectively.
- Many of the less-used commands are now marked as "advanced" and hidden in the help dialog by
  default, so that the core command set is more focused and approachable.
- Improvements to link hinting.
- Bug fixes.

1.21 (2010-10-24)

- Critical bug fix for an excluded URLs regression due to frame support.

1.20 (2010-10-24)

- In link hints mode, holding down the shift key will now toggle between opening in the current tab
  and opening in a new tab.
- Two new commands (`zH` and `zL`) to scroll to the left and right edges of the page.
- A new command (`gi`) to focus the first (or n-th) visible text input.
- A new command (`<a-f>`) to open up multiple links at a time in new tabs.
- Frame support.
- More robust support for non-US keyboard layouts.
- Numerous bug fixes.

1.19 (2010-06-29)

- A critical bug fix for development channel Chromium.
- Vimium icons for the Chrome extensions panel and other places.

1.18 (2010-06-22)

- Vimium now runs on pages with file:/// and ftp:///
- The Options page is now linked from the Help dialog.
- Arrow keys and function keys can now be mapped using &lt;left&gt;, &lt;right&gt;, &lt;up&gt;,
  &lt;down&gt;, &lt;f1&gt;, &lt;f2&gt;, etc. in the mappings interface.
- There is a new command `goUp` (mapped to `gu` by default) that will go up one level in the URL
  hierarchy. For example: from https://vimium.github.io/foo/bar to https://vimium.github.io/foo. At
  the moment, `goUp` does not support command repetition.
- Bug fixes and optimizations.

1.17 (2010-04-18)

- `u` now restores tabs that were closed by the mouse or with native shortcuts. Tabs are also
  restored in their prior position.
- New `unmapAll` command in the key mappings interface to remove all default mappings.
- Link hints are now faster and more reliable.
- Bug fixes.

1.16 (2010-03-09)

- Add support for configurable key mappings under Advanced Options.
- A help dialog which shows all currently bound keyboard shortcuts. Type `?` to see it.
- Bug fixes related to key stroke handling.

1.15 (2010-01-31)

- Make the CSS used by the link hints configurable. It's under Advanced Options.
- Add a notification linking to the changelog when Vimium is updated in the background.
- Link-hinting performance improvements and bug fixes.
- `Ctrl+D` and `Ctrl+U` now scroll by 1/2 page instead of a fixed amount, to mirror Vim's behavior.

1.14 (2010-01-21)

- Fixed a bug introduced in 1.13 that prevented excluded URLs from being saved.

1.13 (2010-01-21)

- `<c-f>` and `<c-b>` are now mapped to scroll a full page up or down respectively.
- Bug fixes related to entering insert mode when the page first loads, and when focusing Flash
  embeds.
- Added command listing to the Options page for easy reference.
- `J` & `K` have reversed for tab switching: `J` goes left and `K` goes right.
- `<c-[>` is now equivalent to `Esc`, to match the behavior of VIM.
- `<c-e>` and `<c-y>` are now mapped to scroll down and up respectively.
- The characters used for link hints are now configurable under Advanced Options.

1.11, 1.12 (2010-01-08)

- Commands `gt` & `gT` to move to the next & previous tab.
- Command `yy` to yank (copy) the current tab's url to the clipboard.
- Better Linux support.
- Fix for `Shift+F` link hints.
- `Esc` now clears the keyQueue. So, for example, hitting `g`, `Esc`, `g` will no longer scroll the
  page.

1.1 (2010-01-03)

- A nicer looking settings page.
- An exclusion list that allows you to define URL patterns for which Vimium will be disabled (e.g.
  http\*://mail.google.com/\*).
- Vimium-interpreted keystrokes are no longer sent to the page.
- Better Windows support.
- Various miscellaneous bug fixes and UI improvements.

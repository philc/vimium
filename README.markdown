Vimium - The Hacker's Browser
=============================

![Build Status](https://travis-ci.org/philc/vimium.png)

Vimium is a Chrome extension that provides keyboard-based navigation and control in the spirit of the Vim
editor.

__Installation instructions:__

You can install the stable version of Vimium from the
[Chrome Extensions Gallery](https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb).

Alternatively, you can install it from source:

1. Install [Coffeescript](http://coffeescript.org/#installation) (needed to build vimium).
2. Run `cake build` in the Vimium directory.
3. Navigate to `chrome://extensions`
4. Toggle into Developer Mode
5. Click on "Load Unpacked Extension..."
6. Select the Vimium directory.

The Options page can be reached via a link on the help dialog (hit `?`) or via the button next to Vimium on
the Chrome Extensions page (`chrome://extensions`).

Keyboard Bindings
-----------------

Modifier keys are specified as `<c-x>`, `<m-x>`, and `<a-x>` for ctrl+x, meta+x, and alt+x
respectively. See the next section for instructions on modifying these bindings.

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
    i       enter insert mode -- all commands will be ignored until you hit esc to exit
    yy      copy the current url to the clipboard
    yf      copy a link url to the clipboard
    gf      cycle forward to the next frame

Navigating to new pages:

    o       Open URL, bookmark, or history entry
    O       Open URL, bookmark, history entry in a new tab
    b       Open bookmark
    B       Open bookmark in a new tab

Using find:

    /       enter find mode -- type your search query and hit enter to search or esc to cancel
            See here for advanced usage (regular expressions): https://github.com/philc/vimium/wiki/Find-Mode
    n       cycle forward to the next find match
    N       cycle backward to the previous find match

Navigating your history:

    H       go back in history
    L       go forward in history

Manipulating tabs:

    J, gT      go one tab left
    K, gt      go one tab right
    g0         go to the first tab
    g$         go to the last tab
    t          create tab
    x          close current tab
    X          restore closed tab (i.e. unwind the 'x' command)
    T          search through your open tabs

Additional advanced browsing commands:

    ]]      Follow the link labeled 'next' or '>'. Helpful for browsing paginated sites.
    [[      Follow the link labeled 'previous' or '<'. Helpful for browsing paginated sites.
    <a-f>   open multiple links in a new tab
    gi      focus the first (or n-th) text input box on the page
    gu      go up one level in the URL hierarchy
    zH      scroll all the way left
    zL      scroll all the way right

Vimium supports command repetition so, for example, hitting '5t' will open 5 tabs in rapid succession. `<ESC>` (or
`<c-[>`) will clear any partial commands in the queue and will also exit insert and find modes.


Custom Key Mappings
-------------------

You may remap or unmap any of the default key bindings in the "Key mappings" section under "Advanced Options"
on the options page.

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

Available Vimium commands can be found via the "Show Available Commands" link near the key mapping box. The
command name appears to the right of the description in parenthesis.

You can add comments to your key mappings by starting a line with `"` or `#`.

The following special keys are available for mapping:

- `<c-*>`, `<a-*>`, `<m-*>` for ctrl, alt, and meta (command on Mac) respectively with any key. Replace `*`
  with the key of choice.
- `<left>`, `<right>`, `<up>`, `<down>` for the arrow keys
- `<f1>` through `<f12>` for the function keys

Shifts are automatically detected so, for example, `<c-&>` corresponds to ctrl+shift+7 on an English keyboard.

Contributing
------------
You'd like to fix a bug or implement a feature? Great! Check out the bugs on our issues tracker, or implement
one of the suggestions there that have been tagged 'todo'. If you have a suggestion of your own, start a
discussion on the issues tracker or on the [mailing list](http://groups.google.com/group/vimium-dev?hl=en). If
it mirrors a similar feature in another browser or in Vim itself, let us know! Once you've picked something to
work on, add a comment to the respective issue so others don't duplicate your effort.

Vimium is written in Coffeescript, which compiles to Javascript. To build Vimium from source:

1. Install [Coffeescript](http://coffeescript.org/#installation).
2. Run `cake autobuild` from within your vimium directory. Any coffeescript files you change will now be automatically compiled to Javascript.

Our tests use [shoulda.js](https://github.com/philc/shoulda.js) and [PhantomJS](http://phantomjs.org/). To run
the tests:

1. `git submodule update --init --recursive` -- this pulls in shoulda.js.
2. [Install PhantomJS.](http://phantomjs.org/download.html)
3. `cake test` to run the tests.

Bugs and features are not the only way to contribute -- more tests are always welcome. You can find out which
portions of code need them by looking at our coverage reports. To generate these reports:

1. Download [JSCoverage](http://siliconforks.com/jscoverage/download.html) or `brew install jscoverage`
2. `npm install temp`
3. `cake coverage` will generate a coverage report in the form of a JSON file (`jscoverage.json`), which can
   then be viewed using [jscoverage-report](https://github.com/int3/jscoverage-report).  See
   jscoverage-report's [README](https://github.com/int3/jscoverage-report#jscoverage-report) for more details.

When you're done with your changes, send us a pull request on Github. Feel free to include a change to the
CREDITS file with your patch.

A few coding style guidelines: 1) follow the style already present in the file, 2) ensure your lines
don't exceed 110 characters.

Release Notes
-------------

1.42 (11/03/2012)

- Bugfixes.

1.41 (10/27/2012)

- Bugfixes.

1.40 (10/27/2012)

- Bugfixes.
- Added options for search engines and regex find.
- Pressing unmapped keys in hints mode now deactivates the mode.

1.39 (09/09/2012)

- Bugfixes.

1.38 (09/08/2012)

- `O` now opens Vomnibar results in a new tab. `B` does the same for bookmarks only.
- Add a browser icon to quickly add sites to Vimium's exclude list.
- Restyle options page.
- `gi` now launches a new mode that allows the user to tab through the input elements on the page.
- Bugfixes.

1.37 (07/07/2012)

- Select the first result by default in Vomnibar tab and bookmark modes.

1.36 (07/07/2012)

- 'b' brings up a bookmark-only Vomnibar.
- Better support for some bookmarklets.

1.35 (07/05/2012)

- Bugfixes.

1.34 (07/03/2012)

- A bugfix for bookmarklets in Vomnibar.

1.33 (07/02/2012)

- A Vomnibar, which allows you to open sites from history, bookmarks, and tabs using Vimium's UI. Type "o" to try it.

1.32 (03/05/2012)

- More tweaks to the next / previous link-detection algorithm.
- Minor bug fixes.

1.31 (02/28/2012)

- Improve style of link hints, and use fewer characters for hints.
- Add an option to hide the heads up display (HUD). Notably, the HUD obscures Facebook Chat's textbox.
- Detection and following of next / previous links has been improved.
- Addition of g0 and g$ commands, for switching tabs.
- Addition of p/P commands for URL pasting.
- A new find mode which optionally supports case sensitivity and regular expressions.
- Bug fixes.

1.30 (12/04/2011)

- Support for image maps in link hints.
- Counts now work with forward & backward navigation.
- Tab & shift-tab to navigate bookmarks dialog.
- An alternate link hints mode: type the title of a link to select it. You can enable it in Vimium's Advanced Preferences.
- Bug fixes.

1.29 (07/30/2011)

- `yf` to copy a link hint url to the clipboard.
- Scatter link hints to prevent clustering on dense sites.
- Don't show insert mode notification unless you specifically hit `i`.
- Remove zooming functionality now that Chrome does it all natively.

1.28 (06/29/2011)

- Support for opening bookmarks (`b` and `B`).
- Support for contenteditable text boxes.
- Speed improvements and bugfixes.

1.27 (03/24/2011)

- Improvements and bugfixes.

1.26 (02/17/2011)

- `<c-d>`, `<c-f>` and related are no longer bound by default. You can rebind them on the options page.
- Faster link hinting.

1.22, 1.23, 1.24, 1.25 (02/10/2011)

-  Some sites are now excluded by default.
-  View source (`gs`) now opens in a new tab.
-  Support for browsing paginated sites using `]]` and `[[` to go forward and backward respectively.
-  Many of the less-used commands are now marked as "advanced" and hidden in the help dialog by default, so
   that the core command set is more focused and approachable.
-  Improvements to link hinting.
-  Bugfixes.

1.21 (10/24/2010)

-  Critical bugfix for an excluded URLs regression due to frame support.

1.20 (10/24/2010)

-  In link hints mode, holding down the shift key will now toggle between opening in the current tab and
   opening in a new tab.
-  Two new commands (`zH` and `zL`) to scroll to the left and right edges of the page.
-  A new command (`gi`) to focus the first (or n-th) text input box on the page.
-  A new command (`<a-f>`) to open up multiple links at a time in new tabs.
-  Frame support.
-  More robust support for non-US keyboard layouts.
-  Numerous bug fixes.

1.19 (06/29/2010)

-  A critical bug fix for development channel Chromium.
-  Vimium icons for the Chrome extensions panel and other places.

1.18 (06/22/2010)

-  Vimium now runs on pages with file:/// and ftp:///
-  The Options page is now linked from the Help dialog.
-  Arrow keys and function keys can now be mapped using &lt;left&gt;, &lt;right&gt;, &lt;up&gt;, &lt;down&gt;,
   &lt;f1&gt;, &lt;f2&gt;, etc. in the mappings interface.
-  There is a new command `goUp` (mapped to `gu` by default) that will go up one level in the URL hierarchy.
   For example: from http://vimium.github.com/foo/bar to http://vimium.github.com/foo. At the moment, `goUp`
does not support command repetition.
-  Bug fixes and optimizations.

1.17 (04/18/2010)

-  'u' now restores tabs that were closed by the mouse or with native shortcuts. Tabs are also restored in
   their prior position.
-  New 'unmapAll' command in the key mappings interface to remove all default mappings.
-  Link hints are now faster and more reliable.
-  Bug fixes.

1.16 (03/09/2010)

-  Add support for configurable key mappings under Advanced Options.
-  A help dialog which shows all currently bound keyboard shortcuts. Type "?" to see it.
-  Bug fixes related to key stroke handling.

1.15 (01/31/2010)

-  Make the CSS used by the link hints configurable. It's under Advanced Options.
-  Add a notification linking to the changelog when Vimium is updated in the background.
-  Link-hinting performance improvements and bugfixes.
-  Ctrl+D and Ctrl+U now scroll by 1/2 page instead of a fixed amount, to mirror Vim's behavior.

1.14 (01/21/2010)

-  Fixed a bug introduced in 1.13 that prevented excluded URLs from being saved.

1.13 (01/21/2010)

- `<c-f>` and `<c-b>` are now mapped to scroll a full page up or down respectively.
-  Bugfixes related to entering insert mode when the page first loads, and when focusing Flash embeds.
-  Added command listing to the Options page for easy reference.
-  J & K have reversed for tab switching: J goes left and K goes right.
-  `<c-[>` is now equivalent to ESC, to match the behavior of VIM.
-  `<c-e>` and `<c-y>` are now mapped to scroll down and up respectively.
-  The characters used for link hints are now configurable under Advanced Options.

1.11, 1.12 (01/08/2010)

-  Commands 'gt' & 'gT' to move to the next & previous tab.
-  Command 'yy' to yank (copy) the current tab's url to the clipboard.
-  Better Linux support.
-  Fix for Shift+F link hints.
-  ESC now clears the keyQueue. So, for example, hitting 'g', 'ESC', 'g' will no longer scroll the page.

1.1 (01/03/2010)

-  A nicer looking settings page.
-  An exclusion list that allows you to define URL patterns for which Vimium will be disabled (e.g.
   http\*://mail.google.com/\*).
-  Vimium-interpreted keystrokes are no longer sent to the page.
-  Better Windows support.
-  Various miscellaneous bug fixes and UI improvements.

License
-------
Copyright (c) 2010 Phil Crosby, Ilya Sukhar. See MIT-LICENSE.txt for details.

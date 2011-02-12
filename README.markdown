Vimium - The Hacker's Browser
=============================

Vimium is a Chrome extension that provides keyboard based navigation and control in the spirit of the Vim
editor.

__Installation instructions:__

You can install the stable version of Vimium from the
[Chrome Extensions Gallery](https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb).

Alternatively, you can install it from source:

1. Navigate to chrome://extensions
2. Click on "Load Extension..."
3. Select the vimium directory.

The Settings page can be found by clicking the Options button next to Vimium on chrome://extensions.

Keyboard Bindings
-----------------

Modifier keys are specified as <c-x>, <m-x>, <a-x> for ctrl+x, meta+x, and alt+x
respectively. You can change any of these shortcuts under "Advanced Options".

Navigating the current page:
    h       scroll left
    j       scroll down
    k       scroll up
    l       scroll right
    gg      scroll to top of the page
    G       scroll to bottom of the page
    d, <c-d>  scroll down half a page
    u, <c-u>  scroll up half a page
    f       open a link in the current tab
    F       open a link in a new tab
    r       reload
    gs      view source
    zi      zoom in
    zo      zoom out
    i       enter insert mode -- all commands will be ignored until you hit esc to exit
    yy      copy the current url to the clipboard
    gf      cycle forward to the next frame

Using find:
    /       enter find mode -- type your search query and hit enter to search or esc to cancel
    n       cycle forward to the next find match
    N       cycle backward to the previous find match

Navigating your history:
    H       go back in history
    L       go forward in history

Manipulating tabs:
    J, gT      go one tab left
    K, gt      go one tab right
    t          create tab
    x          close current tab
    X          restore closed tab (i.e. unwind the 'x' command)

Additional advanced browsing commands:
    ]]      Follow the link labeled 'next' or '>'. Helpful for browsing paginated sites.
    [[      Follow the link labeled 'previous' or '<'. Helpful for browsing paginated sites.
    <a-f>   open multiple links in a new tab
    gi      focus the first (or n-th) text input box on the page
    gu      go up one level in the URL hierarchy
    zH      scroll all the way left
    zL      scroll all the way right
    z0      reset zoom to default value
    <c-f>   scroll down a full page
    <c-b>   scroll up a full page


Vimium supports command repetition so, for example, hitting '5t' will open 5 tabs in rapid succession. ESC (or
<c-[>) will clear any partial commands in the queue.


Contributing
------------

You'd like to fix a bug or implement a feature? Great! Check out the bugs on our issues tracker, or implement
one of the suggestions there that have been tagged 'todo'. If you have a suggestion of your own, start a
discussion on the issues tracker or on the [mailing list][list_url]. If it mirrors a similar feature in
another browser or in Vim itself, let us know! Once you've picked something to work on, add a comment to the
respective issue so others don't duplicate your effort.

When you're done, send us a pull request on Github. Feel free to include a change to the CREDITS file with your patch.

[list_url]: http://groups.google.com/group/vimium-dev?hl=en

Some brief coding style guidelines: 1) follow the style already present in the file, 2) ensure your lines
don't exceed 110 characters.

Release Notes
-------------

1.22, 1.23, 1.24, 1.25 (02/10/2011)

-  Some sites are now excluded by default.
-  View source (`gs`) now opens in a new tab.
-  Support for browsing paginated sites using `]]` and `[[` to go forward and backward respectively.
-  `z0` will reset the zoom level for the current page.
-  Many of the less-used commands are now marked as "advanced" and hidden in the help dialog by default, so that the core command set is more focused and approachable.
-  Improvements to link hinting.
-  Bugfixes.

1.21 (10/24/2010)

-  Critical bugfix for an excluded URLs regression due to frame support.

1.20 (10/24/2010)

-  In link hints mode, holding down the shift key will now toggle between opening in the current tab and opening in a new tab.
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
-  Arrow keys and function keys can now be mapped using &lt;left&gt;, &lt;right&gt;, &lt;up&gt;, &lt;down&gt;, &lt;f1&gt;, &lt;f2&gt;, etc. in the mappings interface.
-  There is a new command `goUp` (mapped to `gu` by default) that will go up one level in the URL hierarchy. For example: from http://vimium.github.com/foo/bar to http://vimium.github.com/foo. At the moment, `goUp` does not support command repetition.
-  Bug fixes and optimizations.

1.17 (04/18/2010)

-  'u' now restores tabs that were closed by the mouse or with native shortcuts. Tabs are also restored in their prior position.
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

-  <c-f> and <c-b> are now mapped to scroll a full page up or down respectively.
-  Bugfixes related to entering insert mode when the page first loads, and when focusing Flash embeds.
-  Added command listing to the Options page for easy reference.
-  J & K have reversed for tab switching: J goes left and K goes right.
-  <c-[> is now equivalent to ESC, to match the behavior of VIM.
-  <c-e> & <c-y> are now mapped to scroll down and up respectively.
-  The characters used for link hints are now configurable under Advanced Options.

1.11, 1.12 (01/08/2010)

-  Commands 'gt' & 'gT' to move to the next & previous tab.
-  Command 'yy' to yank (copy) the current tab's url to the clipboard.
-  Better Linux support.
-  Fix for Shift+F link hints.
-  ESC now clears the keyQueue. So, for example, hitting 'g', 'ESC', 'g' will no longer scroll the page.

1.1 (01/03/2010)

-  A nicer looking settings page.
-  An exclusion list that allows you to define URL patterns for which Vimium will be disabled (e.g.  http\*://mail.google.com/\*).
-  Vimium-interpreted keystrokes are no longer sent to the page.
-  Better Windows support.
-  Various miscellaneous bug fixes and UI improvements.

License
-------
Copyright (c) 2010 Phil Crosby, Ilya Sukhar. See MIT-LICENSE.txt for details.

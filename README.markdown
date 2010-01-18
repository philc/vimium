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

<c-x> is to be interpreted as ctrl + x together.

Navigating the current page:
    h       scroll left
    j       scroll down
    k       scroll up
    l       scroll right
    gg      scroll to top of the page
    G       scroll to bottom of the page
    <c-d>, <c-e>   scroll down a page
    <c-u>, <c-y>   scroll up a page
    <c-f>   scroll down a full page
    <c-b>   scroll up a full page
    f       activate link hints mode to open in current page
    F       activate link hints mode to open in new tab
    r       reload
    gf      view source
    zi      zoom in
    zo      zoom out
    /       enter find mode -- type your search query and hit enter to search or esc to cancel
    n       cycle forward to the next find match
    N       cycle backward to the previous find match
    i       enter insert mode -- all commands will be ignored until you hit esc to exit
    y       copy the current url to the clipboard

Navigating your history:
    ba, H         go back in history
    fw, fo, L     go forward in history

Manipulating tabs:
    J, gT      go one tab left
    K, gt      go one tab right
    t          create tab
    d          close current tab
    u          restore closed tab (i.e. unwind the 'd' command)

Vimium supports command repetition so, for example, hitting '5t' will open 5 tabs in rapid succession. ESC (or
<c-[>) will clear any partial commands in the queue.

Contributing
------------

Send us a pull request on Github with some explanation. If the patch adds new behavior or functionality,
please let us know whether it mirrors a similar extension for another browser or Vim itself. Feel free to
include a change to the CREDITS file with your patch.

Release Notes
-------------

1.13 (Unreleased, current)

-  Commands <c-f> and <c-b> to scroll a full page up or down.
-  Bugfixes related to entering insert mode when the page first loads, and when focusing Flash embeds.
-  Added command listing to the settings page for easy reference.
-  J & K have reversed for tab switching. J goes left and K goes right.
-  <c-[> is now equivalent to ESC.

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

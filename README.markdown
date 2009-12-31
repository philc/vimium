Vimium - The Hacker's Browser
=============================

Vimium is a Chrome extension that provides keyboard based navigation and control in the spirit of the Vim
editor.

Installation Instructions:
  1. Navigate to chrome://extensions
  2. Click on "Load Extension..."
  3. Select the vimium directory.

The settings page can be found by clicking the Options button next to Vimium on chrome://extensions.


Keyboard Bindings
=================

<c-x> is to be interpreted as ctrl + x together.

Navigating the current page:
  h       scroll left
  j       scroll down
  k       scroll up
  l       scroll right
  gg      scroll to top of the page
  G       scroll to bottom of the page
  <c-d>   scroll down a page
  <c-u>   scroll up a page
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

Navigating your history:
  ba, H         go back in history
  fw, fo, L     go forward in history

Manipulating tabs:
  J       next tab
  K       previous tab
  t       create tab
  d       close current tab
  u       restore closed tab (i.e. unwind the 'd' command)

Vimium supports command repetition so, for example, hitting '5t' will open 5 tabs in rapid succession.

License
=======
Copyright (c) 2010 Phil Crosby, Ilya Sukhar. See MIT-LICENSE.txt for details.
# Vimium - The Hacker's Browser

Vimium is a browser extension that provides keyboard-based navigation and control of the web in the
spirit of the Vim editor.

[Watch the demo video](https://www.youtube.com/watch?v=t67Sn0RGK54).

**Installation instructions:**

- Chrome:
  [Chrome web store](https://chromewebstore.google.com/detail/vimium/dbepggeogbaibhgnhhndojpepiihcmeb)
- Edge:
  [Edge Add-ons](https://microsoftedge.microsoft.com/addons/detail/vimium/djmieaghokpkpjfbpelnlkfgfjapaopa)
- Firefox: [Firefox Add-ons](https://addons.mozilla.org/en-GB/firefox/addon/vimium-ff/)

To install from source, see [here](CONTRIBUTING.md#installing-from-source).

Vimium's Options page can be reached via a link on the help dialog (type `?`) or via the button next
to Vimium on the extension pages of Chrome and Edge (`chrome://extensions`), or Firefox
(`about:addons`).

## Keyboard Bindings

Modifier keys are specified as `<c-x>`, `<m-x>`, and `<a-x>` for ctrl+x, meta+x, and alt+x
respectively. For shift+x and ctrl-shift-x, just type `X` and `<c-X>`. See the next section for how
to customize these bindings.

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

For advanced usage, see [regular expressions](https://github.com/philc/vimium/wiki/Find-Mode) on the
wiki.

Navigating your history:

    H       go back in history
    L       go forward in history

Manipulating tabs:

    J, gT   go one tab left
    K, gt   go one tab right
    g0      go to the first tab. Use ng0 to go to n-th tab
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
    gi      focus the first (or n-th) text input box on the page. Use <tab> to cycle through options.
    gu      go up one level in the URL hierarchy
    gU      go up to root of the URL hierarchy
    ge      edit the current URL
    gE      edit the current URL and open in a new tab
    zH      scroll all the way left
    zL      scroll all the way right
    v       enter visual mode; use p/P to paste-and-go, use y to yank
    V       enter visual line mode
    R       Hard reload the page (skip the cache)

Vimium supports command repetition so, for example, hitting `5t` will open 5 tabs in rapid
succession. `<Esc>` (or `<c-[>`) will clear any partial commands in the queue and will also exit
insert and find modes.

There are additional commands which aren't included in this README; refer to the help dialog (type `?`) for a
full list.

## Custom Key Mappings

You may remap or unmap any of the default key bindings in the "Custom key mappings" on the options
page.

Enter one of the following key mapping statements per line:

- `map key command`: Maps a key to a Vimium command. Overrides Chrome's default behavior for that
  key, if any.
- `unmap key`: Unmaps a key and restores Chrome's default behavior (if any).
- `unmapAll`: Unmaps all bindings. This is useful if you want to completely wipe Vimium's defaults
  and start from scratch with your own setup.

Examples:

- `map <c-d> scrollPageDown` maps ctrl+d to scrolling the page down. Chrome's default behavior of
  showing a bookmark dialog is suppressed.
- `map r reload hard` maps the r key to reloading the page, and also includes the "hard"
  option to hard-reload the page.
- `unmap <c-d>` removes any mapping for ctrl+d and restores Chrome's default behavior.
- `unmap r` removes any mapping for the r key.

See the [docs](https://vimium.github.io/commands/) for every Vimium command and its options.

You can add comments to key mappings by starting a line with `"` or `#`.

The following special keys are available for mapping:

- `<c-*>`, `<a-*>`, `<s-*>`, `<m-*>` for ctrl, alt, shift, and meta (command on Mac) respectively
  with any key. Replace `*` with the key of choice.
- `<left>`, `<right>`, `<up>`, `<down>` for the arrow keys.
- `<f1>` through `<f12>` for the function keys.
- `<space>` for the space key.
- `<tab>`, `<enter>`, `<delete>`, `<backspace>`, `<insert>`, `<home>` and `<end>` for the
  corresponding non-printable keys.

Shifts are automatically detected so, for example, `<c-&>` corresponds to ctrl+shift+7 on an English
keyboard.

## More documentation

* [FAQ](https://github.com/philc/vimium/wiki/FAQ)
* [Command listing](https://vimium.github.io/commands/)
* [Vimium's GitHub wiki](https://github.com/philc/vimium/wiki): documentation the more advanced
  features.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Release Notes

See [CHANGELOG](CHANGELOG.md) for the major changes in each release.

## License

Copyright (c) Phil Crosby, Ilya Sukhar. See [MIT-LICENSE.txt](MIT-LICENSE.txt) for details.

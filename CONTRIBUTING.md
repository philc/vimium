# Contributing to Vimium

## Reporting a bug

File the issue [here](https://github.com/philc/vimium/issues).

## Contributing code

You'd like to fix a bug or implement a feature? Great! Before getting started, understand Vimium's design
principles and the goals of the maintainers.

### Vimium design principles

When people first start using Vimium, it provides an incredibly powerful workflow improvement and it makes
them feel awesome. Surprisingly, Vimium is applicable to a huge, broad population of people, not just users of
Vim.

In addition to power, a secondary goal of Vimium is approachability: minimizing the barriers which prevent a
new user from feeling awesome. Many of Vimium's users haven't used Vim before -- about 1 in 5 Chrome Store
reviews say this -- and most people have strong web browsing habits forged from years of browsing. Given that,
it's a great experience when Vimium feels like a natural addition to Chrome which augments, but doesn't break,
the user's current browsing habits.

**Principles:**

1. **Easy to understand**. Even if you're not very familiar with Vim. The Vimium video shows you all you need
   to know to start using Vimium and feel awesome.
2. **Reliable**. The core feature set works on most sites on the web.
3. **Immediately useful**. Vimium doesn't require any configuration or doc-reading before it's useful. Just
   watch the video or hit `?`. You can transition into using Vimium piecemeal; you don't need to jump in
   whole-hog from the start.
4. **Feels native**. Vimium doesn't drastically change the way Chrome looks or behaves.
5. **Simple**. The core feature set isn't overwhelming. This principle is particularly vulnerable as we add to
   Vimium, so it requires our active effort to maintain this simplicity.
6. **Code simplicity**. Developers find the Vimium codebase relatively simple and easy to jump into. This
   provides us an active dev community.

### Which pull requests get merged?

**Goals of the maintainers**

The maintainers of Vimium are @smblott-github and @philc. We have limited bandwidth, which influences which
PRs we can review and merge.

Our goals are generally to keep Vimium small, maintainable, and really nail the broad appeal use cases. This
is in contrast to adding and maintaining an increasing number of complex or niche features. We recommend those
live in forked repos rather than the mainline Vimium repo.

PRs we'll likely merge:

* Reflect all of the Vimium design principles.
* Are useful for lots of Vimium users.
* Have simple implementations (straightforward code, few lines of code).

PRs we likely won't:

* Violate one or more of our design principles.
* Are niche.
* Have complex implementations -- more code than they're worth.

Tips for preparing a PR:

* If you want to check with us first before implementing something big, open an issue proposing the idea.
  You'll get feedback from the maintainers as to whether it's something we'll likely merge.
* Try to keep PRs around 50 LOC or less. Bigger PRs create inertia for review.

### Installing From Source

Vimium is written in Coffeescript, which compiles to Javascript. To
install Vimium from source:

 1. Install [Coffeescript v1](http://coffeescript.org/#installation) (`npm install --global coffeescript@~1`).
 1. Run `./make.js build` from within your vimium directory. Any coffeescript files you change will now be
    automatically compiled to Javascript.

**On Chrome/Chromium:**

 1. Navigate to `chrome://extensions`
 1. Toggle into Developer Mode
 1. Click on "Load Unpacked Extension..."
 1. Select the Vimium directory.

**On Firefox:**

For 'local storage' to work while using the temporary addon, you need to add an 'application' section to the
manifest with an arbitrary ID that is unique for you, for example:

    "applications": {
      "gecko": {
        "id": "vimium@example.net"
      }
    },

After that:

 1. Open Firefox
 1. Enter "about:debugging" in the URL bar
 1. Click "Load Temporary Add-on"
 1. Open the Vimium directory and select any file inside.

### Development tips

 1. Run `./make.js autobuild` to watch for changes to coffee files, and have the .js files automatically
    regenerated

### Running the tests

Our tests use [shoulda.js](https://github.com/philc/shoulda.js) and [PhantomJS](http://phantomjs.org/). To run the tests:

 1. `git submodule update --init --recursive` -- this pulls in shoulda.js.
 1. Install [PhantomJS](http://phantomjs.org/download.html).
 1. `npm install path@0.11` to install the [Node.js Path module](https://nodejs.org/api/path.html), used by the test runner.
 1. `npm install util` to install the [util module](https://www.npmjs.com/package/util), used by the tests.
 1. `./make.js build` to compile `*.coffee` to `*.js`
 1. `./make.js test` to run the tests.

### Coding Style

  * We follow the recommendations from
    [this style guide](https://github.com/polarmobile/coffeescript-style-guide).
  * We follow two major differences from this style guide:
    * Wrap lines at 110 characters instead of 80.
    * Use double-quoted strings by default.
  * When writing comments, uppercase the first letter of your sentence, and put a period at the end.
  * If you have a short conditional, feel free to put it on one line:

        # No
        if i < 10
          return

        # Yes
        return if i < 10

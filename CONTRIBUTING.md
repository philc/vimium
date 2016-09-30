# Contributing to Vimium

You'd like to fix a bug or implement a feature? Great! Check out the bugs on our issues tracker, or implement
one of the suggestions there that have been tagged "help wanted". If you have a suggestion of your own, start
a discussion on the issues tracker or on the
[mailing list](http://groups.google.com/group/vimium-dev?hl=en). If it mirrors a similar feature in another
browser or in Vim itself, let us know. Once you've picked something to work on, add a comment to the
respective issue so others don't duplicate your effort.

## Reporting Issues

Please include the following when reporting an issue:

 1. Chrome and OS Version: `chrome://version`
 1. Vimium Version: `chrome://extensions`

## Installing From Source

Vimium is written in Coffeescript, which compiles to Javascript. To
install Vimium from source:

 1. Install [Coffeescript](http://coffeescript.org/#installation).
 1. Run `cake build` from within your vimium directory. Any coffeescript files you change will now be automatically compiled to Javascript.
 1. Navigate to `chrome://extensions`
 1. Toggle into Developer Mode
 1. Click on "Load Unpacked Extension..."
 1. Select the Vimium directory.

## Development tips

 1. Run `cake autobuild` to watch for changes to coffee files, and have the .js files automatically
    regenerated

## Running the tests

Our tests use [shoulda.js](https://github.com/philc/shoulda.js) and [PhantomJS](http://phantomjs.org/). To run the tests:

 1. `git submodule update --init --recursive` -- this pulls in shoulda.js.
 1. Install [PhantomJS](http://phantomjs.org/download.html).
 1. `npm install path@0.11` to install the [Node.js Path module](http://nodejs.org/api/path.html), used by the test runner.
 1. `npm install util` to install the [util module](https://www.npmjs.com/package/util), used by the tests.
 1. `cake build` to compile `*.coffee` to `*.js`
 1. `cake test` to run the tests.

## Code Coverage

You can find out which portions of code need them by looking at our coverage reports. To generate these
reports:

 1. Download [JSCoverage](http://siliconforks.com/jscoverage/download.html) or `brew install jscoverage`
 1. `npm install temp`
 1. `cake coverage` will generate a coverage report in the form of a JSON file (`jscoverage.json`), which can
    then be viewed using [jscoverage-report](https://github.com/int3/jscoverage-report).  See
    jscoverage-report's [README](https://github.com/int3/jscoverage-report#jscoverage-report) for more details.

## Coding Style

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

## Pull Requests

When you're done with your changes, send us a pull request on Github. Feel free to include a change to the
CREDITS file with your patch.

Vimium design goals
-------------------

When improving Vimium it's helpful to know what design goals we're optimizing for.

The core goal is to make it easy to navigate the web using just the keyboard. When people first start using
Vimium, it provides an incredibly powerful workflow improvement and it makes them feel awesome. And it turns
out that Vimium is applicable to a huge, broad population of people, not just users of Vim, which is great.

A secondary goal is to make Vimium approachable, or in other words, to minimize the barriers which will
prevent a new user from feeling awesome. Many of Vimium's users haven't used Vim before (about 1 in 5 app
store reviews say this), and most people have strong web browsing habits forged from years of browsing that
they rely on. Given that, it's a great experience when Vimium feels like a natural addition to Chrome which
augments but doesn't break their current browsing habits.

In some ways, making software approachable is even harder than just enabling the core use case. But in this
area, Vimium really shines. It's approachable today because:

1. It's simple to understand (even if you're not very familiar with Vim). The Vimium video shows you all you
   need to know to start using Vimium and feel awesome.
2. The core feature set works in almost all cases on all sites, so Vimium feels reliable.
3. Requires no configuration or doc-reading before it's useful. Just watch the video or hit `?`.
4. Doesn't drastically change the way Chrome looks or behaves. You can transition into using Vimium piecemeal;
   you don't need to jump in whole-hog from the start.
5. The core feature set isn't overwhelming. This is easy to degrade as we evolve Vimium, so it requires active
   effort to maintain this feel.
6. Developers find the code is relatively simple and easy to jump into, so we have an active dev community.

## What makes for a good feature request/contribution to Vimium?

Good features:

* Useful for lots of Vimium users
* Require no/little documentation
* Useful without configuration
* Intuitive or leverage strong convention from Vim
* Work robustly on most/all sites

Less-good features:

* Are very niche, and so aren't useful for many Vimium users
* Require explanation
* Require configuration before it becomes useful
* Unintuitive, or they don't leverage a strong convention from Vim
* Might be flaky and don't work in many cases

We use these guidelines, in addition to the code complexity, when deciding whether to merge in a pull request.

If you're worried that a feature you plan to build won't be a good fit for core Vimium, just open a github
issue for discussion or send an email to the Vimium mailing list.

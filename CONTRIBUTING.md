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
 1. `npm install path` to install the [Node.js Path module](http://nodejs.org/api/path.html), used by the test runner.
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

## Pull Requests

When you're done with your changes, send us a pull request on Github. Feel free to include a change to the
CREDITS file with your patch.

## How to release Vimium to the Chrome Store

This process is currently only done by Phil or Ilya.

1. Increment the version number in manifest.json
2. Update the Changelog in README.md

    You can see a summary of commits since the last version: `git log --oneline v1.45..`

3. Push your commits
4. Create a git tag for this newly released version

        git tag -a v1.45 -m "v1.45 release"

5. Run `cake package`
6. Take the distributable found in `dist` and upload it
   [here](https://chrome.google.com/webstore/developer/dashboard)
7. Update the description in the Chrome store to include the latest version's release notes
8. Celebrate

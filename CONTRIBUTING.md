# Contributing to Vimium

You'd like to fix a bug or implement a feature? Great! Check out the bugs on our issues tracker, or implement
one of the suggestions there that have been tagged 'todo'. If you have a suggestion of your own, start a
discussion on the issues tracker or on the [mailing list](http://groups.google.com/group/vimium-dev?hl=en). If
it mirrors a similar feature in another browser or in Vim itself, let us know! Once you've picked something to
work on, add a comment to the respective issue so others don't duplicate your effort.

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

## Tests

Our tests use [shoulda.js](https://github.com/philc/shoulda.js) and [PhantomJS](http://phantomjs.org/). To run the tests:

 1. `git submodule update --init --recursive` -- this pulls in shoulda.js.
 1. [Install PhantomJS.](http://phantomjs.org/download.html)
 1. `cake build` to compile `*.coffee` to `*.js`
 1. `cake test` to run the tests.

## Code Coverage

Bugs and features are not the only way to contribute -- more tests are always welcome. You can find out which
portions of code need them by looking at our coverage reports. To generate these reports:

 1. Download [JSCoverage](http://siliconforks.com/jscoverage/download.html) or `brew install jscoverage`
 1. `npm install temp`
 1. `cake coverage` will generate a coverage report in the form of a JSON file (`jscoverage.json`), which can
    then be viewed using [jscoverage-report](https://github.com/int3/jscoverage-report).  See
    jscoverage-report's [README](https://github.com/int3/jscoverage-report#jscoverage-report) for more details.

## Pull Requests

When you're done with your changes, send us a pull request on Github. Feel free to include a change to the
CREDITS file with your patch.

## Coding Style

  * We follow the recommendations from
    [this style guide](https://github.com/polarmobile/coffeescript-style-guide).
  * We follow two major differences from this style guide:
    * Wrap lines at 110 characters instead of 80.
    * Use double-quoted strings by default.

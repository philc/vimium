# Development Environment


## Installing From Source

Vimium is written in Coffeescript, which compiles to Javascript. To
install Vimium from source:


 1. Install [Coffeescript v1](http://coffeescript.org/#installation) To install, first make sure you have a working copy of the latest stable version of [Node.js](https://nodejs.org). You can then install CoffeeScript globally with npm:(`npm install --global coffeescript@~1`).
 1. Run `cake build` from within your vimium directory. Any coffeescript files you change will now be automatically compiled to Javascript.

### Chrome/Chromium

 1. Navigate to `chrome://extensions`
 1. Toggle into Developer Mode
 1. Click on "Load Unpacked Extension..."
 1. Select the Vimium directory.

### Firefox

For 'local storage' to work while using the temporary addon, you need to add an
'application' section to the manifest with an arbitrary ID that is unique for
you, for example:

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

## Development tips

 1. Run `cake autobuild` to watch for changes to coffee files, and have the .js files automatically
    regenerated

## Running the tests

Our tests use [shoulda.js](https://github.com/philc/shoulda.js) and [PhantomJS](http://phantomjs.org/). To run the tests:

 1. `git submodule update --init --recursive` -- this pulls in shoulda.js.
 1. Install [PhantomJS](http://phantomjs.org/download.html).
 1. `npm install path@0.11` to install the [Node.js Path module](https://nodejs.org/api/path.html), used by the test runner.
 1. `npm install util` to install the [util module](https://www.npmjs.com/package/util), used by the tests.
 1. `cake build` to compile `*.coffee` to `*.js`
 1. `cake test` to run the tests.

## Code Coverage

You can find out which portions of code need them by looking at our coverage reports. To generate these
reports:

 1. Download [JSCoverage](https://siliconforks.com/jscoverage/download.html) or `brew install jscoverage`
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
require "./test_helper.js"
extend(global, require "../../lib/utils.js")

context "isUrl",
  should "accept valid URLs", ->
    assert.isTrue Utils.isUrl "www.google.com"
    assert.isTrue Utils.isUrl "www.bbc.co.uk"
    assert.isTrue Utils.isUrl "yahoo.com"
    assert.isTrue Utils.isUrl "nunames.nu"
    assert.isTrue Utils.isUrl "user:pass@ftp.xyz.com/test"

    assert.isTrue Utils.isUrl "localhost/index.html"
    assert.isTrue Utils.isUrl "127.0.0.1:8192/test.php"

    # IPv6
    assert.isTrue Utils.isUrl "[::]:9000"

    # Long TLDs
    assert.isTrue Utils.isUrl "illinois.state.museum"
    assert.isTrue Utils.isUrl "eqt5g4fuenphqinx.onion"

  should "reject invalid URLs", ->
    assert.isFalse Utils.isUrl "a.x"
    assert.isFalse Utils.isUrl "www-domain-tld"

context "convertToUrl",
  should "detect and clean up valid URLs", ->
    assert.equal "http://www.google.com/", Utils.convertToUrl("http://www.google.com/")
    assert.equal "http://www.google.com/", Utils.convertToUrl("    http://www.google.com/     ")
    assert.equal "http://www.google.com", Utils.convertToUrl("www.google.com")
    assert.equal "http://google.com", Utils.convertToUrl("google.com")
    assert.equal "http://localhost", Utils.convertToUrl("localhost")
    assert.equal "http://xyz.museum", Utils.convertToUrl("xyz.museum")
    assert.equal "chrome://extensions", Utils.convertToUrl("chrome://extensions")
    assert.equal "http://user:pass@ftp.xyz.com/test", Utils.convertToUrl("user:pass@ftp.xyz.com/test")
    assert.equal "http://127.0.0.1", Utils.convertToUrl("127.0.0.1")
    assert.equal "http://127.0.0.1:8080", Utils.convertToUrl("127.0.0.1:8080")
    assert.equal "http://[::]:8080", Utils.convertToUrl("[::]:8080")

  should "convert non-URL terms into search queries", ->
    assert.equal "http://www.google.com/search?q=google", Utils.convertToUrl("google")
    assert.equal "http://www.google.com/search?q=go%20ogle.com", Utils.convertToUrl("go ogle.com")

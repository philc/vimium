require "./test_helper.js"
extend(global, require "../lib/utils.js")

context "convertToUrl",
  should "detect and clean up valid URLs", ->
    assert.equal "http://www.google.com/", utils.convertToUrl("http://www.google.com/")
    assert.equal "http://www.google.com/", utils.convertToUrl("    http://www.google.com/     ")
    assert.equal "http://www.google.com", utils.convertToUrl("www.google.com")
    assert.equal "http://google.com", utils.convertToUrl("google.com")
    assert.equal "http://localhost", utils.convertToUrl("localhost")
    assert.equal "http://xyz.museum", utils.convertToUrl("xyz.museum")
    assert.equal "chrome://extensions", utils.convertToUrl("chrome://extensions")
    assert.equal "http://user:pass@ftp.xyz.com/test", utils.convertToUrl("user:pass@ftp.xyz.com/test")
    assert.equal "http://127.0.0.1", utils.convertToUrl("127.0.0.1")
    assert.equal "http://127.0.0.1:8080", utils.convertToUrl("127.0.0.1:8080")
    assert.equal "http://[::]:8080", utils.convertToUrl("[::]:8080")

  should "convert non-URL terms into search queries", ->
    assert.equal "http://www.google.com/search?q=google", utils.convertToUrl("google")
    assert.equal "http://www.google.com/search?q=go%20ogle.com", utils.convertToUrl("go ogle.com")

import "./test_helper.js";
import "../../lib/settings.js";
import "../../lib/url_utils.js";

context("isUrl", () => {
  should("accept valid URLs", async () => {
    assert.isTrue(await UrlUtils.isUrl("www.google.com"));
    assert.isTrue(await UrlUtils.isUrl("www.bbc.co.uk"));
    assert.isTrue(await UrlUtils.isUrl("yahoo.com"));
    assert.isTrue(await UrlUtils.isUrl("nunames.nu"));
    assert.isTrue(await UrlUtils.isUrl("user:pass@ftp.xyz.com/test"));

    assert.isTrue(await UrlUtils.isUrl("localhost/index.html"));
    assert.isTrue(await UrlUtils.isUrl("127.0.0.1:8192/test.php"));

    // IPv6
    assert.isTrue(await UrlUtils.isUrl("[::]:9000"));

    // Long TLDs
    assert.isTrue(await UrlUtils.isUrl("testing.social"));
    assert.isTrue(await UrlUtils.isUrl("testing.onion"));

    // // Internal URLs.
    assert.isTrue(
      await UrlUtils.isUrl(
        "moz-extension://c66906b4-3785-4a60-97bc-094a6366017e/pages/options.html",
      ),
    );
  });

  should("reject invalid URLs", async () => {
    assert.isFalse(await UrlUtils.isUrl("a.x"));
    assert.isFalse(await UrlUtils.isUrl("www-domain-tld"));
    assert.isFalse(await UrlUtils.isUrl("http://www.example.com/ has-space"));
  });
});

context("convertToUrl", async () => {
  should("detect and clean up valid URLs", async () => {
    assert.equal("http://www.google.com/", await UrlUtils.convertToUrl("http://www.google.com/"));
    assert.equal(
      "http://www.google.com/",
      await UrlUtils.convertToUrl("    http://www.google.com/     "),
    );
    assert.equal("http://www.google.com", await UrlUtils.convertToUrl("www.google.com"));
    assert.equal("http://google.com", await UrlUtils.convertToUrl("google.com"));
    assert.equal("http://localhost", await UrlUtils.convertToUrl("localhost"));
    assert.equal("http://xyz.museum", await UrlUtils.convertToUrl("xyz.museum"));
    assert.equal("chrome://extensions", await UrlUtils.convertToUrl("chrome://extensions"));
    assert.equal(
      "http://user:pass@ftp.xyz.com/test",
      await UrlUtils.convertToUrl("user:pass@ftp.xyz.com/test"),
    );
    assert.equal("http://127.0.0.1", await UrlUtils.convertToUrl("127.0.0.1"));
    assert.equal("http://127.0.0.1:8080", await UrlUtils.convertToUrl("127.0.0.1:8080"));
    assert.equal("http://[::]:8080", await UrlUtils.convertToUrl("[::]:8080"));
    assert.equal("view-source:    0.0.0.0", await UrlUtils.convertToUrl("view-source:    0.0.0.0"));
    assert.equal(
      "javascript:alert('25 % 20 * 25%20');",
      await UrlUtils.convertToUrl("javascript:alert('25 % 20 * 25%20');"),
    );
  });
});

context("createSearchUrl", () => {
  should("replace %S without encoding", () => {
    assert.equal(
      "https://www.github.com/philc/vimium/pulls",
      UrlUtils.createSearchUrl("vimium/pulls", "https://www.github.com/philc/%S"),
    );
  });
});

context("hasChromePrefix", () => {
  should("detect chrome prefixes of URLs", () => {
    assert.isTrue(UrlUtils.hasChromePrefix("about:foobar"));
    assert.isTrue(UrlUtils.hasChromePrefix("view-source:foobar"));
    assert.isTrue(UrlUtils.hasChromePrefix("chrome-extension:foobar"));
    assert.isTrue(UrlUtils.hasChromePrefix("data:foobar"));
    assert.isTrue(UrlUtils.hasChromePrefix("data:"));
    assert.isFalse(UrlUtils.hasChromePrefix(""));
    assert.isFalse(UrlUtils.hasChromePrefix("about"));
    assert.isFalse(UrlUtils.hasChromePrefix("view-source"));
    assert.isFalse(UrlUtils.hasChromePrefix("chrome-extension"));
    assert.isFalse(UrlUtils.hasChromePrefix("data"));
    assert.isFalse(UrlUtils.hasChromePrefix("data :foobar"));
  });
});

context("hasJavascriptPrefix", () => {
  should("detect javascript: URLs", () => {
    assert.isTrue(UrlUtils.hasJavascriptPrefix("javascript:foobar"));
    assert.isFalse(UrlUtils.hasJavascriptPrefix("http:foobar"));
  });
});

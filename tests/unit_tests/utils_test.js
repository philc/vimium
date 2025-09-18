import "./test_helper.js";
import "../../lib/settings.js";
import "../../lib/url_utils.js";

context("forTrusted", () => {
  should("invoke an event handler if the event is trusted", () => {
    let called = false;
    const f = forTrusted(() => called = true);
    const event = { isTrusted: true };
    f(event);
    assert.equal(true, called);
  });

  should("not invoke an event handler if the event is untrusted", () => {
    let called = false;
    const f = forTrusted(() => called = true);
    const event = { isTrusted: false };
    f(event);
    assert.equal(false, called);
    f(null);
    assert.equal(false, called);
  });
});

context("extractQuery", () => {
  should("extract queries from search URLs", () => {
    assert.equal(
      "bbc sport 1",
      Utils.extractQuery(
        "https://www.google.ie/search?q=%s",
        "https://www.google.ie/search?q=bbc+sport+1",
      ),
    );
    assert.equal(
      "bbc sport 2",
      Utils.extractQuery(
        "http://www.google.ie/search?q=%s",
        "https://www.google.ie/search?q=bbc+sport+2",
      ),
    );
    assert.equal(
      "bbc sport 3",
      Utils.extractQuery(
        "https://www.google.ie/search?q=%s",
        "http://www.google.ie/search?q=bbc+sport+3",
      ),
    );
    assert.equal(
      "bbc sport 4",
      Utils.extractQuery(
        "https://www.google.ie/search?q=%s",
        "http://www.google.ie/search?q=bbc+sport+4&blah",
      ),
    );
  });
});

context("decodeURIByParts", () => {
  should("decode javascript: URLs", () => {
    assert.equal("foobar", Utils.decodeURIByParts("foobar"));
    assert.equal(" ", Utils.decodeURIByParts("%20"));
    assert.equal("25 % 20 25 ", Utils.decodeURIByParts("25 % 20 25%20"));
  });
});

context("compare versions", () => {
  should("compare correctly", () => {
    assert.equal(0, Utils.compareVersions("1.40.1", "1.40.1"));
    assert.equal(0, Utils.compareVersions("1.40", "1.40.0"));
    assert.equal(0, Utils.compareVersions("1.40.0", "1.40"));
    assert.equal(-1, Utils.compareVersions("1.40.1", "1.40.2"));
    assert.equal(-1, Utils.compareVersions("1.40.1", "1.41"));
    assert.equal(-1, Utils.compareVersions("1.40", "1.40.1"));
    assert.equal(1, Utils.compareVersions("1.41", "1.40"));
    assert.equal(1, Utils.compareVersions("1.41.0", "1.40"));
    assert.equal(1, Utils.compareVersions("1.41.1", "1.41"));
  });
});

context("makeIdempotent", () => {
  let func;
  let count = 0;

  setup(() => {
    count = 0;
    func = Utils.makeIdempotent((n) => {
      if (n == null) {
        n = 1;
      }
      count += n;
    });
  });

  should("call a function once", () => {
    func();
    assert.equal(1, count);
  });

  should("call a function once with an argument", () => {
    func(2);
    assert.equal(2, count);
  });

  should("not call a function a second time", () => {
    func();
    assert.equal(1, count);
  });

  should("not call a function a second time", () => {
    func();
    assert.equal(1, count);
    func();
    assert.equal(1, count);
  });
});

context("distinctCharacters", () => {
  should(
    "eliminate duplicate characters",
    () => assert.equal("abc", Utils.distinctCharacters("bbabaabbacabbbab")),
  );
});

context("escapeRegexSpecialCharacters", () => {
  should("escape regexp special characters", () => {
    const str = "-[]/{}()*+?.^$|";
    const regexp = new RegExp(Utils.escapeRegexSpecialCharacters(str));
    assert.isTrue(regexp.test(str));
  });
});

context("extractQuery", () => {
  should("extract the query terms from a URL", () => {
    const url = "https://www.google.ie/search?q=star+wars&foo&bar";
    const searchUrl = "https://www.google.ie/search?q=%s";
    assert.equal("star wars", Utils.extractQuery(searchUrl, url));
  });

  should("require trailing URL components", () => {
    const url = "https://www.google.ie/search?q=star+wars&foo&bar";
    const searchUrl = "https://www.google.ie/search?q=%s&foobar=x";
    assert.equal(null, Utils.extractQuery(searchUrl, url));
  });

  should("accept trailing URL components", () => {
    const url = "https://www.google.ie/search?q=star+wars&foo&bar&foobar=x";
    const searchUrl = "https://www.google.ie/search?q=%s&foobar=x";
    assert.equal("star wars", Utils.extractQuery(searchUrl, url));
  });
});

context("pick", () => {
  should("omit properties", () => {
    assert.equal({ a: 1, b: 2 }, Utils.pick({ a: 1, b: 2, c: 3 }, ["a", "b", "d"]));
  });
});

context("keyBy", () => {
  const array = [
    { key: "a" },
    { key: "b" },
  ];

  should("group by string key", () => {
    assert.equal(
      { a: array[0], b: array[1] },
      Utils.keyBy(array, "key"),
    );
  });

  should("group by key function", () => {
    assert.equal(
      { a: array[0], b: array[1] },
      Utils.keyBy(array, (el) => el.key),
    );
  });
});

context("assertType", () => {
  should("fail if schema or object is null", () => {
    assert.throwsError(() => Utils.assertType(null, { a: 1 }));
    assert.throwsError(() => Utils.assertType({ a: null }, null));
  });

  should("not allow unknown fields", () => {
    const schema = { a: null };
    Utils.assertType(schema, { a: 1 });
    assert.throwsError(() => Utils.assertType(schema, { b: 1 }));
  });

  should("type check fields with types", () => {
    const schema = {
      bool: "boolean",
      num: "number",
      string: "string"
    };
    Utils.assertType(schema, {
      bool: true,
      num: 1,
      string: "example"
    });
    assert.throwsError(() => Utils.assertType(schema, { bool: 1 }));
    assert.throwsError(() => Utils.assertType(schema, { num: "example" }));
    assert.throwsError(() => Utils.assertType(schema, { string: 1 }));
  });

  should("allow null values for typed fields", () => {
    Utils.assertType({ bool: "boolean" }, { bool: null });
  });
});

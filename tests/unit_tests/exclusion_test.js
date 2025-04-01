import "./test_helper.js";

Utils.getCurrentVersion = () => "1.44";

import "../../lib/settings.js";
import "../../background_scripts/bg_utils.js";
import * as exclusions from "../../background_scripts/exclusions.js";
import "../../background_scripts/commands.js";

const isEnabledForUrl = (request) => exclusions.isEnabledForUrl(request.url);

// These tests cover only the most basic aspects of excluded URLs and passKeys.
context("Excluded URLs and pass keys", () => {
  setup(async () => {
    await Settings.onLoaded();
    await Settings.set("exclusionRules", [
      { pattern: "http*://mail.google.com/*", passKeys: "" },
      { pattern: "http*://www.facebook.com/*", passKeys: "abab" },
      { pattern: "http*://www.facebook.com/*", passKeys: "cdcd" },
      { pattern: "http*://www.bbc.com/*", passKeys: "" },
      { pattern: "http*://www.bbc.com/*", passKeys: "ab" },
      { pattern: "http*://www.example.com/*", passKeys: "a bb c bba a" },
      { pattern: "http*://www.duplicate.com/*", passKeys: "ace" },
      { pattern: "http*://www.duplicate.com/*", passKeys: "bdf" },
    ]);
  });

  teardown(async () => {
    await Settings.clear();
  });

  should("be disabled for excluded sites", () => {
    const rule = isEnabledForUrl({ url: "http://mail.google.com/calendar/page" });
    assert.isFalse(rule.isEnabledForUrl);
    assert.isFalse(rule.passKeys);
  });

  should("be disabled for excluded sites, one exclusion", () => {
    const rule = isEnabledForUrl({ url: "http://www.bbc.com/calendar/page" });
    assert.isFalse(rule.isEnabledForUrl);
    assert.isFalse(rule.passKeys);
  });

  should("be enabled, but with pass keys", () => {
    const rule = isEnabledForUrl({ url: "https://www.facebook.com/something" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.equal(rule.passKeys, "abcd");
  });

  should("be enabled", () => {
    const rule = isEnabledForUrl({ url: "http://www.twitter.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.isFalse(rule.passKeys);
  });

  should("handle spaces and duplicates in passkeys", () => {
    const rule = isEnabledForUrl({ url: "http://www.example.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.equal("abc", rule.passKeys);
  });

  should("handle multiple passkeys rules", () => {
    const rule = isEnabledForUrl({ url: "http://www.duplicate.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.equal("abcdef", rule.passKeys);
  });

  should("be enabled when given malformed regular expressions", async () => {
    await Settings.set("exclusionRules", [
      { pattern: "http*://www.bad-regexp.com/*[a-", passKeys: "" },
    ]);
    const rule = isEnabledForUrl({ url: "http://www.bad-regexp.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
  });
});

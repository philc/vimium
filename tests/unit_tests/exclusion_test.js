import "./test_helper.js";
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
      { pattern: "http*://mail.google.com/*", passKeys: "", blockedKeys: "" },
      { pattern: "http*://www.facebook.com/*", passKeys: "abab", blockedKeys: "" },
      { pattern: "http*://www.facebook.com/*", passKeys: "cdcd", blockedKeys: " ff " },
      { pattern: "http*://www.bbc.com/*", passKeys: "", blockedKeys: "" },
      { pattern: "http*://www.bbc.com/*", passKeys: "ab", blockedKeys: "c" },
      { pattern: "http*://www.example.com/*", passKeys: "a bb c bba a", blockedKeys: " ff " },
      { pattern: "http*://www.duplicate.com/*", passKeys: "ace", blockedKeys: "xz" },
      { pattern: "http*://www.duplicate.com/*", passKeys: "bdf", blockedKeys: "zy" },
    ]);
  });

  teardown(async () => {
    await Settings.clear();
  });

  should("be disabled for excluded sites", () => {
    const rule = isEnabledForUrl({ url: "http://mail.google.com/calendar/page" });
    assert.isFalse(rule.isEnabledForUrl);
    assert.isFalse(rule.passKeys);
    assert.equal("", rule.blockedKeys);
  });

  should("be disabled for excluded sites, one exclusion", () => {
    const rule = isEnabledForUrl({ url: "http://www.bbc.com/calendar/page" });
    assert.isFalse(rule.isEnabledForUrl);
    assert.isFalse(rule.passKeys);
    assert.equal("", rule.blockedKeys);
  });

  should("be enabled, but with pass keys", () => {
    const rule = isEnabledForUrl({ url: "https://www.facebook.com/something" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.equal(rule.passKeys, "abcd");
    assert.equal(rule.blockedKeys, "f");
  });

  should("be enabled", () => {
    const rule = isEnabledForUrl({ url: "http://www.twitter.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.isFalse(rule.passKeys);
    assert.equal(rule.blockedKeys, "");
  });

  should("handle spaces and duplicates in passkeys", () => {
    const rule = isEnabledForUrl({ url: "http://www.example.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.equal("abc", rule.passKeys);
    assert.equal("f", rule.blockedKeys);
  });

  should("handle multiple passkeys rules", () => {
    const rule = isEnabledForUrl({ url: "http://www.duplicate.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
    assert.equal("abcdef", rule.passKeys);
    assert.equal("xyz", rule.blockedKeys);
  });

  should("be enabled when given malformed regular expressions", async () => {
    await Settings.set("exclusionRules", [
      { pattern: "http*://www.bad-regexp.com/*[a-", passKeys: "", blockedKeys: "" },
    ]);
    const rule = isEnabledForUrl({ url: "http://www.bad-regexp.com/pages" });
    assert.isTrue(rule.isEnabledForUrl);
  });
});

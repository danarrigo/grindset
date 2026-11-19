import test from "node:test";
import assert from "node:assert/strict";
import {websiteHost, hostFromUrl, buildRules, restrictionForHost} from "./policy.js";

test("only host identifiers leave URL parsing", () => {
  assert.equal(hostFromUrl("https://www.Example.com/private/path?secret=value#fragment"), "example.com");
  assert.equal(websiteHost("https://example.com/private"), null);
  assert.equal(websiteHost("example.com/path"), null);
  assert.equal(websiteHost("example.com?query"), null);
  assert.equal(websiteHost("example..com"), null);
  assert.equal(hostFromUrl("chrome://settings"), null);
  assert.equal(hostFromUrl("file:///private.txt"), null);
});

test("blocking uses domain conditions and has no way around it", () => {
  // An old app's "allowed" list is ignored: there is no temporary override.
  const rules = buildRules({enabled: true, blocked: [{domain: "example.com"}, {domain: "another.com"}], allowed: ["example.com"]}, "chrome-extension://fixture/blocked.html");
  assert.equal(rules.length, 2);
  assert.ok(rules.every(rule => rule.action.type === "redirect"));
  assert.deepEqual(rules.map(rule => rule.condition.requestDomains[0]), ["another.com", "example.com"]);
});

test("an already-open subdomain is restricted without matching an unrelated suffix", () => {
  const config = {enabled: true, blocked: [{domain: "example.com", reason: "Focus"}]};
  assert.equal(restrictionForHost(config, "m.example.com")?.reason, "Focus");
  assert.equal(restrictionForHost(config, "example.com.evil.test"), null);
  assert.equal(restrictionForHost({...config, allowed: ["example.com"]}, "m.example.com")?.reason, "Focus");
});

test("disconnecting or disabling tracking clears all website rules", () => {
  assert.deepEqual(buildRules({enabled: false, blocked: [{domain: "example.com"}], allowed: ["example.com"]}, "unused"), []);
});

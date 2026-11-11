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

test("blocking uses domain conditions and a source-specific override wins", () => {
  const rules = buildRules({enabled: true, blocked: [{domain: "example.com"}, {domain: "another.com"}], allowed: ["example.com"]}, "chrome-extension://fixture/blocked.html");
  assert.equal(rules.length, 3);
  const block = rules.find(rule => rule.condition.requestDomains[0] === "example.com" && rule.action.type === "redirect");
  const allow = rules.find(rule => rule.action.type === "allow");
  assert.ok(allow.priority > block.priority);
  assert.deepEqual(allow.condition.requestDomains, ["example.com"]);
  assert.ok(rules.some(rule => rule.action.type === "redirect" && rule.condition.requestDomains[0] === "another.com"));
});

test("an already-open subdomain is restricted without matching an unrelated suffix", () => {
  const config = {enabled: true, blocked: [{domain: "example.com", reason: "Focus"}], allowed: []};
  assert.equal(restrictionForHost(config, "m.example.com")?.reason, "Focus");
  assert.equal(restrictionForHost(config, "example.com.evil.test"), null);
  assert.equal(restrictionForHost({...config, allowed: ["example.com"]}, "m.example.com"), null);
});

test("disconnecting or disabling tracking clears all website rules", () => {
  assert.deepEqual(buildRules({enabled: false, blocked: [{domain: "example.com"}], allowed: ["example.com"]}, "unused"), []);
});

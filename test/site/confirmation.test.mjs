import test from "node:test";
import assert from "node:assert/strict";
import { confirmationState } from "../../site/confirmed/confirmation.mjs";

test("callback distinguishes verified, expired and direct visits", () => {
  assert.equal(confirmationState("?code=not-a-real-code", "").title, "Email confirmed");
  assert.equal(confirmationState("", "#type=signup&access_token=not-a-real-token").title, "Email confirmed");
  assert.equal(confirmationState("", "#error=access_denied&error_code=otp_expired").title, "This link could not be confirmed");
  assert.equal(confirmationState("?code=not-a-real-code&error_description=failed", "").title, "This link could not be confirmed");
  assert.equal(confirmationState("", "").title, "Return to Grindset");
  assert.equal(confirmationState("?code=", "").title, "Return to Grindset");
  assert.equal(confirmationState("", "#type=recovery&access_token=not-a-real-token").title, "Return to Grindset");
});

test("URL input is never reflected in the page text", () => {
  const state = confirmationState("?error_description=%3Cscript%3Esecret-marker%3C/script%3E", "");
  assert.ok(!JSON.stringify(state).includes("secret-marker"));
});

test("browser callback removes both query and fragment before rendering", async () => {
  const events = [];
  globalThis.window = {
    location: { search: "?code=not-a-real-code", hash: "#access_token=not-a-real-token", pathname: "/grindset-releases/confirmed/" },
    history: { replaceState: (_state, _title, path) => events.push(["clean-url", path]) },
  };
  globalThis.document = {
    getElementById: (id) => ({ set textContent(value) { events.push([id, value]); } }),
  };
  try {
    await import("../../site/confirmed/confirmation.mjs?browser-test");
    assert.deepEqual(events[0], ["clean-url", "/grindset-releases/confirmed/"]);
    assert.equal(events[1][1], "Email confirmed");
    assert.ok(!JSON.stringify(events).includes("not-a-real"));
  } finally {
    delete globalThis.window;
    delete globalThis.document;
  }
});

import test from "node:test";
import assert from "node:assert/strict";
import { recoveryToken, requestReset, setPassword } from "../../site/reset-password/reset.mjs";
import { recoveryRedirect } from "../../site/confirmed/confirmation.mjs";
import { project } from "../../site/delete-account/delete.mjs";

function server(replies) {
  const calls = [];
  const fetch = async (url, options) => {
    calls.push({ url, options });
    const reply = replies.shift();
    if (reply instanceof Error) throw reply;
    return { ok: reply.status < 300, status: reply.status, json: async () => reply.body ?? {} };
  };
  return { calls, fetch };
}

test("only a recovery link carries a usable token", () => {
  assert.equal(recoveryToken("#access_token=t&type=recovery"), "t");
  assert.equal(recoveryToken("#access_token=t&type=signup"), null);
  assert.equal(recoveryToken(""), null);
});

test("a recovery link landing on the confirmation page moves to the reset page", () => {
  assert.equal(recoveryRedirect("#access_token=t&type=recovery"), "../reset-password/#access_token=t&type=recovery");
  assert.equal(recoveryRedirect("#access_token=t&type=signup"), null);
});

test("reset email asks to come back to this page and never reveals whether the account exists", async () => {
  const { calls, fetch } = server([{ status: 200 }]);
  const result = await requestReset(fetch, "a@example.test");
  assert.equal(result.ok, true);
  assert.ok(calls[0].url.startsWith(`${project}/auth/v1/recover?redirect_to=`));
  assert.ok(decodeURIComponent(calls[0].url).endsWith("/grindset-releases/reset-password/"));
  assert.deepEqual(JSON.parse(calls[0].options.body), { email: "a@example.test" });
  assert.match((await requestReset(server([{ status: 429 }]).fetch, "a")).message, /Too many/);
});

test("new password is saved with the link's sign-in, and failures explain why", async () => {
  const { calls, fetch } = server([{ status: 200 }]);
  assert.equal((await setPassword(fetch, "tok", "longenough")).ok, true);
  assert.equal(calls[0].options.method, "PUT");
  assert.equal(calls[0].options.headers.Authorization, "Bearer tok");
  assert.match((await setPassword(fetch, "tok", "123")).message, /at least 6/);
  assert.match((await setPassword(server([{ status: 401 }]).fetch, "old", "longenough")).message, /expired/);
  assert.match((await setPassword(server([{ status: 422, body: { msg: "New password should be different from the old password." } }]).fetch, "t", "longenough")).message, /different/);
});

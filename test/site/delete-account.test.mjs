import test from "node:test";
import assert from "node:assert/strict";
import { deleteAccount, project } from "../../site/delete-account/delete.mjs";

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

test("signs in, then deletes with that session", async () => {
  const { calls, fetch } = server([{ status: 200, body: { access_token: "fixture-token" } }, { status: 204 }]);
  const result = await deleteAccount(fetch, "a@example.test", "pw");
  assert.equal(result.ok, true);
  assert.equal(calls[0].url, `${project}/auth/v1/token?grant_type=password`);
  assert.deepEqual(JSON.parse(calls[0].options.body), { email: "a@example.test", password: "pw" });
  assert.equal(calls[1].url, `${project}/rest/v1/rpc/delete_account`);
  assert.equal(calls[1].options.headers.Authorization, "Bearer fixture-token");
});

test("a wrong password deletes nothing", async () => {
  const { calls, fetch } = server([{ status: 400, body: { error_description: "Invalid login credentials" } }]);
  const result = await deleteAccount(fetch, "a@example.test", "wrong");
  assert.equal(result.ok, false);
  assert.match(result.message, /did not match/);
  assert.equal(calls.length, 1);
});

test("an unconfirmed email is explained", async () => {
  const { fetch } = server([{ status: 400, body: { msg: "Email not confirmed" } }]);
  assert.match((await deleteAccount(fetch, "a@example.test", "pw")).message, /never confirmed/);
});

test("server and network failures say nothing was deleted", async () => {
  let { fetch } = server([{ status: 200, body: { access_token: "t" } }, { status: 500 }]);
  assert.match((await deleteAccount(fetch, "a", "b")).message, /Nothing was deleted/);
  ({ fetch } = server([new TypeError("offline")]));
  assert.equal((await deleteAccount(fetch, "a", "b")).ok, false);
});

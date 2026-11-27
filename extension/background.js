import {hostFromUrl, buildRules, restrictionForHost} from "./policy.js";

const base = "http://127.0.0.1:47831/v1";
// Firefox and its forks (Zen, LibreWolf, Floorp, Waterfox) all report "Firefox/".
const browser = navigator.userAgent.includes("Firefox/") ? "firefox" : navigator.userAgent.includes("Edg/") ? "edge" : "chrome";
let syncing;
let policyUpdate = Promise.resolve();

async function request(path, body, paired = true, timeout = 4000) {
  const {token} = await chrome.storage.local.get("token");
  if (paired && !token) throw new Error("Pair this browser with Grindset first.");
  const response = await fetch(base + path, {
    method: body === undefined ? "GET" : "POST",
    headers: {"Content-Type": "application/json", ...(paired ? {Authorization: `Bearer ${token}`} : {})},
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store", signal: AbortSignal.timeout(timeout),
  });
  if (response.status === 401) await chrome.storage.local.remove("token");
  if (!response.ok) throw new Error(response.status === 401 ? "Pair this browser with Grindset again." : "Open Grindset and check the local connection or pairing code.");
  return response.json();
}

function apply(config) {
  policyUpdate = policyUpdate.catch(() => {}).then(async () => {
    const previous = await chrome.declarativeNetRequest.getDynamicRules();
    await chrome.declarativeNetRequest.updateDynamicRules({removeRuleIds: previous.map(rule => rule.id), addRules: buildRules(config, chrome.runtime.getURL("blocked.html"))});
    await chrome.action.setBadgeText({text: config.enabled ? "" : "OFF"});
    await chrome.action.setTitle({title: config.enabled ? "Grindset - paired" : "Grindset - tracking is off"});
    const [tab] = await chrome.tabs.query({active: true, lastFocusedWindow: true});
    const window = tab ? await chrome.windows.get(tab.windowId) : null;
    const domain = hostFromUrl(tab?.url);
    if (window?.focused && restrictionForHost(config, domain)) {
      await chrome.tabs.update(tab.id, {url: `${chrome.runtime.getURL("blocked.html")}#${encodeURIComponent(domain)}|${tab.url}`});
    }
  });
  return policyUpdate;
}

async function unavailable() {
  // Closing/quitting the native app must not leave an unbounded stale block.
  await apply({enabled: false});
  await chrome.action.setTitle({title: "Grindset - native app disconnected; blocking is unavailable"});
}

async function refresh() {
  if (syncing) return syncing;
  syncing = (async () => {
    try { const config = await request("/rules"); await apply(config); return config; }
    catch (error) { await unavailable(); throw error; }
  })().finally(() => { syncing = undefined; });
  return syncing;
}

async function report(sender, message = {}) {
  const [tab] = await chrome.tabs.query({active: true, lastFocusedWindow: true});
  const window = tab ? await chrome.windows.get(tab.windowId) : null;
  const locked = await chrome.idle.queryState(180) === "locked";
  const accepted = !sender?.tab || (sender.tab.id === tab?.id && sender.frameId === 0);
  if (!accepted) return;
  const domain = tab?.url ? hostFromUrl(tab.url) : null;
  const focused = Boolean(domain && window?.focused && !locked && message.focused !== false);
  await request("/heartbeat", {browser, domain: focused ? domain : null, focused, mediaPlaying: focused && message.mediaPlaying === true});
  await refresh();
}

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  (async () => {
    if (message.type === "heartbeat" && sender.tab) { await report(sender, message); return {ok: true}; }
    if (message.type === "pair" && sender.url === chrome.runtime.getURL("setup.html")) {
      if (!/^\d{6}$/.test(message.code)) throw new Error("Enter the six-digit code shown by Grindset.");
      const {token} = await request("/pair", {code: message.code}, false);
      await chrome.storage.local.set({token});
      await refresh();
      return {ok: true};
    }
    if (sender.url?.startsWith(chrome.runtime.getURL("blocked.html")) && message.type === "refresh") {
      return {ok: true, config: await refresh()};
    }
    if (sender.url?.startsWith(chrome.runtime.getURL("blocked.html")) && message.type === "close" && sender.tab) {
      await chrome.tabs.remove(sender.tab.id);
      return {ok: true};
    }
    if (sender.url?.startsWith(chrome.runtime.getURL("blocked.html")) && message.type === "pass") {
      // The AI can take up to half a minute.
      const verdict = await request("/pass", {domain: message.domain, reason: message.reason}, true, 35000);
      if (verdict.allow) {
        // A refresh already under way may predate the pass.
        await syncing?.catch(() => {});
        await refresh();
      }
      return {ok: true, verdict};
    }
    throw new Error("Unsupported Grindset request.");
  })().then(reply, error => reply({ok: false, error: error.message}));
  return true;
});

async function wake() {
  // Chrome only; Firefox never exposes extension storage to content scripts.
  await chrome.storage.local.setAccessLevel?.({accessLevel: "TRUSTED_CONTEXTS"});
  await chrome.alarms.create("lockin", {periodInMinutes: 0.5});
  await refresh().catch(() => {});
}
chrome.runtime.onInstalled.addListener(wake);
chrome.runtime.onStartup.addListener(wake);
chrome.alarms.onAlarm.addListener(() => refresh().catch(() => {}));
chrome.tabs.onActivated.addListener(() => report().catch(unavailable));
chrome.tabs.onUpdated.addListener((_id, change) => { if (change.url || change.status === "complete") report().catch(unavailable); });
chrome.windows.onFocusChanged.addListener(() => report().catch(unavailable));
chrome.idle.onStateChanged.addListener(() => report().catch(unavailable));
chrome.action.onClicked.addListener(() => chrome.runtime.openOptionsPage());

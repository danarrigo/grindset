import {hostFromUrl, buildRules, websiteHost, restrictionForHost} from "./policy.js";

const base = "http://127.0.0.1:47831/v1";
const browser = navigator.userAgent.includes("Edg/") ? "edge" : "chrome";
let syncing;
let policyUpdate = Promise.resolve();

async function request(path, body, paired = true) {
  const {token} = await chrome.storage.local.get("token");
  if (paired && !token) throw new Error("Pair this browser with Lockin first.");
  const response = await fetch(base + path, {
    method: body === undefined ? "GET" : "POST",
    headers: {"Content-Type": "application/json", ...(paired ? {Authorization: `Bearer ${token}`} : {})},
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: "no-store", signal: AbortSignal.timeout(4000),
  });
  if (response.status === 401) await chrome.storage.local.remove("token");
  if (!response.ok) throw new Error(response.status === 401 ? "Pair this browser with Lockin again." : "Open Lockin and check the local connection or pairing code.");
  return response.json();
}

function apply(config) {
  policyUpdate = policyUpdate.catch(() => {}).then(async () => {
    const previous = await chrome.declarativeNetRequest.getDynamicRules();
    await chrome.declarativeNetRequest.updateDynamicRules({removeRuleIds: previous.map(rule => rule.id), addRules: buildRules(config, chrome.runtime.getURL("blocked.html"))});
    await chrome.action.setBadgeText({text: config.enabled ? "" : "OFF"});
    await chrome.action.setTitle({title: config.enabled ? "Lockin - paired" : "Lockin - tracking is off"});
    const [tab] = await chrome.tabs.query({active: true, lastFocusedWindow: true});
    const window = tab ? await chrome.windows.get(tab.windowId) : null;
    const domain = hostFromUrl(tab?.url);
    if (window?.focused && restrictionForHost(config, domain)) {
      await chrome.tabs.update(tab.id, {url: `${chrome.runtime.getURL("blocked.html")}#${encodeURIComponent(domain)}`});
    }
  });
  return policyUpdate;
}

async function unavailable() {
  // Closing/quitting the native app must not leave an unbounded stale block.
  await apply({enabled: false});
  await chrome.action.setTitle({title: "Lockin - native app disconnected; blocking is unavailable"});
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
      if (!/^\d{6}$/.test(message.code)) throw new Error("Enter the six-digit code shown by Lockin.");
      const {token} = await request("/pair", {code: message.code}, false);
      await chrome.storage.local.set({token});
      await refresh();
      return {ok: true};
    }
    if (sender.url?.startsWith(chrome.runtime.getURL("blocked.html"))) {
      if (message.type === "override") {
        const domain = websiteHost(message.domain);
        if (!domain) throw new Error("Invalid website identifier.");
        const config = await request("/override", {domain});
        await apply(config);
        return {ok: true};
      }
      if (message.type === "refresh") return {ok: true, config: await refresh()};
    }
    throw new Error("Unsupported Lockin request.");
  })().then(reply, error => reply({ok: false, error: error.message}));
  return true;
});

async function wake() {
  await chrome.storage.local.setAccessLevel({accessLevel: "TRUSTED_CONTEXTS"});
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

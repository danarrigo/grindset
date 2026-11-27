import {blockedTarget, restrictionForHost} from "./policy.js";
const {domain, back} = blockedTarget(location.hash.slice(1));
const $ = id => document.querySelector(`#${id}`);
$("domain").textContent = domain ?? "Unknown website";
let entry;
let pause = 0;
let left = null;
let asking = false;

// The same pause as in the app: it starts again when this page is hidden.
function wait() { left = pause; update(); }
function update() {
  const ready = left <= 0 && $("why").value.trim() && !asking;
  $("send").disabled = !ready;
  $("send").textContent = asking ? "Asking AI…" : left > 0 ? `Wait ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : "Ask AI for a few minutes";
}
setInterval(() => { if (left > 0 && document.visibilityState === "visible") { left--; update(); } }, 1000);
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden" && left !== null) wait(); });
$("why").addEventListener("input", update);

$("ask").addEventListener("submit", async event => {
  event.preventDefault();
  asking = true; $("verdict").textContent = ""; update();
  try {
    const result = await chrome.runtime.sendMessage({type: "pass", domain: entry.domain, reason: $("why").value.trim()});
    if (!result.ok) throw new Error(result.error);
    if (result.verdict.allow) { location.replace(back); return; }
    $("verdict").textContent = result.verdict.message || "Not this time.";
    wait();
  } catch (error) { $("verdict").textContent = error.message; }
  finally { asking = false; update(); }
});

async function refresh() {
  const result = await chrome.runtime.sendMessage({type: "refresh"});
  if (!result.ok) { $("status").textContent = result.error; return; }
  entry = restrictionForHost(result.config, domain);
  $("reason").textContent = entry?.reason ?? "The restriction is no longer active. You can reopen the website.";
  const canAsk = Boolean(entry && result.config.askAi);
  if (canAsk && $("ask").hidden) { pause = result.config.pause ?? 0; wait(); }
  $("ask").hidden = !canAsk;
  $("stays").textContent = canAsk ? "Otherwise this website stays blocked until your rule ends." : "This website stays blocked until your rule ends.";
}
setInterval(() => refresh().catch(() => {}), 2000);
refresh().catch(() => {});

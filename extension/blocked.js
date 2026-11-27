import {blockedTarget, restrictionForHost} from "./policy.js";
const {domain, back} = blockedTarget(location.hash.slice(1));
const $ = id => document.querySelector(`#${id}`);
let entry;
let pause = 0;
let left = null;
let asking = false;

// The same pause as in the app: it starts again when this page is hidden.
function wait() { left = pause; update(); }
function update() {
  const ready = left <= 0 && $("why").value.trim() && !asking;
  $("send").disabled = !ready;
  $("send").textContent = asking ? "Asking AI…" : left > 0 ? `Wait ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}` : "Ask AI";
}
setInterval(() => { if (left > 0 && document.visibilityState === "visible") { left--; update(); } }, 1000);
document.addEventListener("visibilitychange", () => { if (document.visibilityState === "hidden" && left !== null) wait(); });
$("why").addEventListener("input", update);
$("need").addEventListener("click", () => { $("need").hidden = true; $("ask").hidden = false; wait(); $("why").focus(); });
// Once the block is over, the same button opens the site instead.
let ended = false;
$("back").addEventListener("click", () => ended ? location.replace(back) : chrome.runtime.sendMessage({type: "close"}));

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

function minutesLeft(until) {
  const minutes = Math.floor((until - Date.now()) / 60000);
  if (minutes < 1) return "Under a minute";
  if (minutes < 60) return `${minutes} min`;
  return minutes % 60 ? `${Math.floor(minutes / 60)} hr ${minutes % 60} min` : `${minutes / 60} hr`;
}

function draw() {
  const name = entry?.name ?? domain ?? "this site";
  $("title").textContent = `Not now,\n${name}.`;
  $("title").classList.toggle("long", name.length > 14);
  document.title = `Not now, ${name} - Grindset`;
  const until = entry?.until ? Date.parse(entry.until) : NaN;
  const from = entry?.from ? Date.parse(entry.from) : NaN;
  $("span").hidden = !entry?.label || Number.isNaN(until);
  $("reason").hidden = !$("span").hidden;
  if (!$("span").hidden) {
    const part = Number.isNaN(from) ? 1 : Math.min(Math.max((Date.now() - from) / (until - from), 0), 1);
    $("done").style.flexGrow = part;
    $("rest").style.flexGrow = 1 - part;
    $("bar").classList.toggle("whole", part <= 0.001 || part >= 0.999);
    $("bar").setAttribute("aria-label", `${Math.round(part * 100)} percent through`);
    $("label").textContent = entry.label;
    $("detail").textContent = Number.isNaN(from) ? "Opens again tomorrow" : `${minutesLeft(until)} left · ends ${new Date(until).toLocaleTimeString([], {hour: "numeric", minute: "2-digit"})}`;
  }
  $("reason").textContent = entry?.reason ?? "The block has ended. You can open the site again.";
}

async function refresh() {
  const result = await chrome.runtime.sendMessage({type: "refresh"});
  if (!result.ok) { $("status").textContent = result.error; return; }
  $("status").textContent = "";
  entry = restrictionForHost(result.config, domain);
  const canAsk = Boolean(entry && result.config.askAi);
  if (canAsk) pause = result.config.pause ?? 0;
  if (!canAsk) { $("need").hidden = true; $("ask").hidden = true; }
  else if ($("ask").hidden) $("need").hidden = false;
  ended = !entry;
  $("back").textContent = ended ? "Open the site" : "Back to work";
  draw();
}
setInterval(() => refresh().catch(() => {}), 2000);
draw();
refresh().catch(() => {});

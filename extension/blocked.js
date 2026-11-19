import {websiteHost} from "./policy.js";
const domain = websiteHost(decodeURIComponent(location.hash.slice(1)));
document.querySelector("#domain").textContent = domain ?? "Unknown website";
async function refresh() {
  const result = await chrome.runtime.sendMessage({type: "refresh"});
  if (!result.ok) { document.querySelector("#status").textContent = result.error; return; }
  const entry = result.config.blocked.find(rule => rule.domain === domain);
  document.querySelector("#reason").textContent = entry?.reason ?? "The restriction is no longer active. You can reopen the website.";
}
setInterval(() => refresh().catch(() => {}), 2000);
refresh().catch(() => {});

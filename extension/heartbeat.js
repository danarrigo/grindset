// No text, titles, URLs or media metadata are sent from the page.
function report() {
  const focused = document.visibilityState === "visible" && document.hasFocus();
  const mediaPlaying = focused && [...document.querySelectorAll("video,audio")].some(media => !media.paused && !media.ended && media.readyState >= 2);
  chrome.runtime.sendMessage({type: "heartbeat", focused, mediaPlaying}).catch(() => {});
}
setInterval(report, 5000);
document.addEventListener("visibilitychange", report);
window.addEventListener("focus", report);
window.addEventListener("blur", report);
report();

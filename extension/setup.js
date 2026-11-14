document.querySelector("#pair").addEventListener("submit", async event => {
  event.preventDefault();
  const button = document.querySelector("button"), status = document.querySelector("#status");
  button.disabled = true;
  try {
    const result = await chrome.runtime.sendMessage({type: "pair", code: document.querySelector("#code").value.trim()});
    status.textContent = result.ok ? "Paired. Tracking and rules follow the Windows app." : result.error;
  } catch { status.textContent = "Could not connect. Open Grindset and try again."; }
  finally { button.disabled = false; }
});

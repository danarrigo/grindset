document.querySelector("#pair").addEventListener("submit", async event => {
  event.preventDefault();
  const button = document.querySelector("button"), status = document.querySelector("#status");
  button.disabled = true;
  // Firefox-based browsers grant site access only on request, and only during
  // this click. Chrome and Edge already have it, so this resolves at once.
  const access = chrome.permissions.request({origins: chrome.runtime.getManifest().host_permissions}).catch(() => true);
  try {
    if (!await access) {
      status.textContent = "Allow access to websites so Grindset can see which site is open and block it.";
      return;
    }
    const result = await chrome.runtime.sendMessage({type: "pair", code: document.querySelector("#code").value.trim()});
    status.textContent = result.ok ? "Paired. Tracking and rules follow the Windows app." : result.error;
  } catch { status.textContent = "Could not connect. Open Grindset and try again."; }
  finally { button.disabled = false; }
});

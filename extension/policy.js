export function websiteHost(value) {
  if (typeof value !== "string") return null;
  let host = value.toLowerCase().replace(/\.$/, "").replace(/^www\./, "");
  if (!host || host.length > 253) return null;
  return host.split(".").every(part => /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(part)) ? host : null;
}

export function hostFromUrl(value) {
  try {
    const url = new URL(value);
    return ["http:", "https:"].includes(url.protocol) ? websiteHost(url.hostname) : null;
  } catch { return null; }
}

export function restrictionForHost(config, value) {
  const host = websiteHost(value);
  const matches = domain => { const root = websiteHost(domain); return root && (host === root || host?.endsWith(`.${root}`)); };
  if (!config.enabled || !host) return null;
  return (config.blocked ?? []).find(entry => matches(entry.domain)) ?? null;
}

export function buildRules(config, blockedPage) {
  if (!config.enabled) return [];
  const blocked = [...new Set((config.blocked ?? []).map(entry => websiteHost(entry.domain)).filter(Boolean))].sort();
  let id = 1;
  return [
    ...blocked.map(domain => ({id: id++, priority: 1, action: {type: "redirect", redirect: {url: `${blockedPage}#${encodeURIComponent(domain)}`}}, condition: {requestDomains: [domain], resourceTypes: ["main_frame"]}})),
  ];
}

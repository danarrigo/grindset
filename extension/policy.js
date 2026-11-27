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
    // The blocked page keeps the address, to go back to if an AI allows a few minutes.
    ...blocked.map(domain => ({id: id++, priority: 1, action: {type: "redirect", redirect: {regexSubstitution: `${blockedPage}#${encodeURIComponent(domain)}|\\0`}}, condition: {regexFilter: "^https?://.*$", requestDomains: [domain], resourceTypes: ["main_frame"]}})),
  ];
}

/** The blocked page's hash: the site, then the address it was going to. */
export function blockedTarget(hash) {
  const split = hash.indexOf("|");
  const domain = websiteHost(decodeURIComponent(split < 0 ? hash : hash.slice(0, split)));
  const wanted = split < 0 ? null : hash.slice(split + 1);
  // Only ever back to the blocked site itself.
  const same = domain && restrictionForHost({enabled: true, blocked: [{domain}]}, hostFromUrl(wanted));
  return {domain, back: same ? wanted : domain ? `https://${domain}/` : null};
}

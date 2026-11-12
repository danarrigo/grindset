"""Write the optional public client configuration for native build jobs."""
import base64
import json
import os
import pathlib
import sys

url = os.environ.get("SUPABASE_URL", "")
key = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
if bool(url) != bool(key):
    raise SystemExit("Configure both public Supabase variables, or neither for local mode.")
if key and not key.startswith("sb_publishable_"):
    try:
        payload = key.split(".")[1]
        role = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))["role"]
    except Exception:
        raise SystemExit("Use a public publishable or legacy anon key, never an admin key.")
    if role != "anon":
        raise SystemExit("Privileged Supabase keys must never be built into a client.")
pathlib.Path(sys.argv[1]).write_text(json.dumps({
    "SUPABASE_URL": url, "SUPABASE_PUBLISHABLE_KEY": key,
}), encoding="utf-8")

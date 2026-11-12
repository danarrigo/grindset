"""Real permission-loss checks on the dedicated, already opted-in test AVD.

Run: python3 test/native/android_tracking_permissions_test.py /path/to/adb.exe
This changes permissions only for Lockin on Lockin_Test_API_36_1. It does not
install, uninstall, clear data, or prove the consent/onboarding UI flow.
"""

import argparse
import json
import pathlib
import re
import sqlite3
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("adb")
args = parser.parse_args()
PACKAGE = "app.lockin.lockin"
SERIAL = "emulator-5556"
root = pathlib.Path(tempfile.mkdtemp(prefix="lockin-android-permissions-"))


def adb(*arguments):
    return subprocess.check_output(
        [args.adb, "-s", SERIAL, *arguments], text=True, timeout=20
    ).strip()


def preferences():
    value = adb("exec-out", "run-as", PACKAGE, "dd", "if=shared_prefs/lockin_runtime.xml")
    return {entry.attrib["name"]: entry.attrib.get("value", entry.text) for entry in ET.fromstring(value)}


def foreground():
    services = adb("shell", "dumpsys", "activity", "services")
    record = re.search(
        r"ServiceRecord\{[^\n]*app\.lockin\.lockin/\.TrackingService[^\n]*\n(.*?)(?=\n  \* ServiceRecord|\Z)",
        services,
        re.S,
    )
    return bool(record and "isForeground=true" in record.group(1))


def snapshot(label):
    directory = root / label
    directory.mkdir()
    for suffix in ["", "-wal"]:
        target = directory / ("lockin.sqlite" + suffix)
        with target.open("wb") as output:
            result = subprocess.run(
                [args.adb, "-s", SERIAL, "exec-out", "run-as", PACKAGE, "dd", "if=files/lockin.sqlite" + suffix],
                stdout=output, stderr=subprocess.DEVNULL, timeout=20,
            )
        if result.returncode:
            target.unlink(missing_ok=True)
    return directory / "lockin.sqlite"


def checkpoint(database):
    with sqlite3.connect(database) as db:
        row = db.execute("SELECT value FROM settings WHERE key='android_imported_until'").fetchone()
    return row[0] if row else None


def resume():
    adb("shell", "am", "start", "-n", PACKAGE + "/.MainActivity")
    for _ in range(20):
        if foreground():
            break
        time.sleep(1)
    else:
        raise AssertionError("Opted-in collector did not become foreground")
    adb("shell", "input", "keyevent", "KEYCODE_HOME")
    adb("shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", "https://example.org/", "-p", "com.android.chrome")
    time.sleep(18)


def denied_window(label, deny, restore, message):
    before = checkpoint(snapshot(label + "-before"))
    assert before, "The baseline collector has not imported usage"
    deny()
    denied_from = (int(adb("shell", "date", "+%s")) + 1) * 1000
    time.sleep(5)
    first = checkpoint(snapshot(label + "-settled"))
    time.sleep(18)
    last = checkpoint(snapshot(label + "-denied"))
    state = preferences()
    print(json.dumps({"case": label, "collectorForeground": foreground(), "checkpointSettled": first, "checkpointLater": last, "interruption": state.get("error")}), flush=True)
    assert not foreground(), "Collector stayed foreground after permission loss"
    assert first == last, "Usage importer continued while permission was denied"
    assert state.get("enabled") == "true", "Permission loss unexpectedly discarded the opt-in"
    assert "enabled_since" not in state, "Denied collection window remained open"
    assert message in state.get("error", ""), "Persistent interruption reason is missing"
    denied_until = int(adb("shell", "date", "+%s")) * 1000
    restore()
    resume()
    after = snapshot(label + "-restored")
    assert checkpoint(after) > last, "Import did not resume after permission restoration"
    with sqlite3.connect(after) as db:
        overlap = db.execute(
            "SELECT count(*) FROM intervals WHERE source LIKE 'android:%' AND start_ms < ? AND end_ms > ?",
            [denied_until, denied_from],
        ).fetchone()[0]
    assert overlap == 0, "Resuming backfilled the permission-disabled gap"
    assert preferences().get("error") is None, "Resolved interruption reason was not cleared"
    print("PASS:", label, "stopped, recovered, and left the denied gap empty", flush=True)


assert adb("emu", "avd", "name").splitlines()[0] == "Lockin_Test_API_36_1", "Refusing to modify any other device"
assert int(adb("shell", "getprop", "ro.build.version.sdk")) >= 33
assert preferences().get("enabled") == "true", "Explicitly opt in on the dedicated fixture before running"
assert "GET_USAGE_STATS: allow" in adb("shell", "cmd", "appops", "get", PACKAGE, "GET_USAGE_STATS")
assert re.search(r"POST_NOTIFICATIONS: granted=true", adb("shell", "dumpsys", "package", PACKAGE))
adb("shell", "input", "keyevent", "KEYCODE_WAKEUP")
adb("shell", "wm", "dismiss-keyguard")
try:
    resume()
    denied_window(
        "notification-permission",
        lambda: adb("shell", "pm", "revoke", PACKAGE, "android.permission.POST_NOTIFICATIONS"),
        lambda: adb("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS"),
        "notifications",
    )
    denied_window(
        "usage-access",
        lambda: adb("shell", "cmd", "appops", "set", PACKAGE, "GET_USAGE_STATS", "ignore"),
        lambda: adb("shell", "cmd", "appops", "set", PACKAGE, "GET_USAGE_STATS", "allow"),
        "Usage Access",
    )
finally:
    adb("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
    adb("shell", "cmd", "appops", "set", PACKAGE, "GET_USAGE_STATS", "allow")
    print("Isolated journal evidence:", root, flush=True)

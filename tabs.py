#!/usr/bin/env python3
"""Print the default browser's most recently used tabs as a JSON array.

Usage: tabs.py [limit]
Each entry: {title, url, host, icon, at}; `at` is when it was last looked at
(ms since the epoch), `icon` a file:// favicon or "". Newest first, one per
URL, web pages only. Favicons the browser keeps as data: URIs are written out
to ~/.cache/clawdius/favicons, nothing is fetched.

Firefox and its forks: the open tabs, from the session store (recovery.jsonlz4
while it runs, sessionstore.jsonlz4 once it's closed). Chromium and its forks
keep their session in a format of their own; for them it's the pages visited
last, from History. Anything else: an empty list.
"""
import base64
import configparser
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
from urllib.parse import urlsplit

LIMIT = int(sys.argv[1]) if len(sys.argv) > 1 else 6
HOME = os.path.expanduser("~")
ICONS = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "clawdius", "favicons")

FIREFOX_ROOTS = {
    "firefox": [".config/mozilla/firefox", ".mozilla/firefox"],
    "librewolf": [".config/librewolf/librewolf", ".librewolf"],
    "zen": [".config/zen", ".zen"],
    "floorp": [".floorp"],
    "waterfox": [".waterfox"],
}
CHROMIUM_DIRS = {
    "chromium": ".config/chromium",
    "google-chrome": ".config/google-chrome",
    "brave": ".config/BraveSoftware/Brave-Browser",
    "vivaldi": ".config/vivaldi",
    "microsoft-edge": ".config/microsoft-edge",
    "helium": ".config/net.imput.helium",
}


def default_browser():
    for argv in (["omarchy-cmd-default-browser"], ["xdg-mime", "query", "default", "x-scheme-handler/https"]):
        try:
            out = subprocess.run(argv, capture_output=True, text=True, timeout=2).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            continue
        if out:
            return out.lower()
    return ""


def lz4_block(src, size):
    """Decompress one LZ4 block (no lz4 module on a stock install)."""
    out = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]
        i += 1
        run = token >> 4
        if run == 15:
            while True:
                b = src[i]
                i += 1
                run += b
                if b != 255:
                    break
        out += src[i:i + run]
        i += run
        if i >= n:
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        match = (token & 15) + 4
        if match == 19:
            while True:
                b = src[i]
                i += 1
                match += b
                if b != 255:
                    break
        start = len(out) - offset
        if offset >= match:
            out += out[start:start + match]
        else:
            for k in range(match):
                out.append(out[start + k])
    return bytes(out[:size])


def mozlz4(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"mozLz40\0":
        raise ValueError("not mozlz4")
    return json.loads(lz4_block(data[12:], int.from_bytes(data[8:12], "little")))


def icon_file(uri):
    """A data: favicon as a cached file's URL; "" for anything else."""
    if not uri.startswith("data:image/") or ";base64," not in uri:
        return ""
    kind, data = uri[len("data:image/"):].split(";base64,", 1)
    ext = {"svg+xml": "svg", "x-icon": "ico", "vnd.microsoft.icon": "ico", "jpeg": "jpg"}.get(kind, kind)
    if not ext.isalnum():
        return ""
    path = os.path.join(ICONS, hashlib.sha1(data.encode()).hexdigest()[:16] + "." + ext)
    if not os.path.exists(path):
        try:
            os.makedirs(ICONS, exist_ok=True)
            with open(path + ".tmp", "wb") as f:
                f.write(base64.b64decode(data))
            os.replace(path + ".tmp", path)
        except (OSError, ValueError):
            return ""
    return "file://" + path


def firefox_profile(root):
    ini = configparser.ConfigParser()
    if not ini.read(os.path.join(root, "profiles.ini")):
        return None
    paths = [ini[s].get("Default") for s in ini.sections() if s.startswith("Install") and ini[s].get("Default")]
    paths += [ini[s].get("Path") for s in ini.sections() if s.startswith("Profile") and ini[s].get("Default") == "1"]
    paths += [ini[s].get("Path") for s in ini.sections() if s.startswith("Profile") and ini[s].get("Path")]
    for p in paths:
        full = p if os.path.isabs(p) else os.path.join(root, p)
        if os.path.isdir(full):
            return full
    return None


def firefox_tabs(roots):
    for root in roots:
        profile = firefox_profile(os.path.join(HOME, root))
        if not profile:
            continue
        for name in ("sessionstore-backups/recovery.jsonlz4", "sessionstore.jsonlz4", "sessionstore-backups/previous.jsonlz4"):
            try:
                session = mozlz4(os.path.join(profile, name))
            except (OSError, ValueError, IndexError):
                continue
            tabs = []
            for window in session.get("windows", []):
                for tab in window.get("tabs", []):
                    entries = tab.get("entries") or []
                    if not entries:
                        continue
                    entry = entries[max(0, min(len(entries), tab.get("index", len(entries))) - 1)]
                    tabs.append({
                        "title": entry.get("title") or "",
                        "url": entry.get("url") or "",
                        "image": tab.get("image") or "",
                        "at": tab.get("lastAccessed") or 0,
                    })
            return tabs
    return []


def chromium_tabs(path):
    db = os.path.join(HOME, path, "Default", "History")
    if not os.path.exists(db):
        return []
    try:
        # immutable: it's locked while the browser runs.
        con = sqlite3.connect("file:%s?immutable=1" % db, uri=True)
        rows = con.execute("SELECT url, title, last_visit_time FROM urls WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT 60").fetchall()
        con.close()
    except sqlite3.Error:
        return []
    # Microseconds since 1601.
    return [{"title": t or "", "url": u, "image": "", "at": int(v / 1000 - 11644473600000)} for u, t, v in rows]


def main():
    browser = default_browser()
    tabs = []
    for key, roots in FIREFOX_ROOTS.items():
        if key in browser:
            tabs = firefox_tabs(roots)
            break
    else:
        for key, path in CHROMIUM_DIRS.items():
            if key in browser:
                tabs = chromium_tabs(path)
                break

    seen, out = set(), []
    for tab in sorted(tabs, key=lambda t: t["at"], reverse=True):
        url = tab["url"]
        parts = urlsplit(url)
        if parts.scheme not in ("http", "https") or url in seen:
            continue
        seen.add(url)
        host = parts.hostname or ""
        if host.startswith("www."):
            host = host[4:]
        tab["host"] = host
        tab["title"] = tab["title"].strip() or host
        tab["icon"] = icon_file(tab.pop("image"))
        out.append(tab)
        if len(out) >= LIMIT:
            break
    print(json.dumps(out))


if __name__ == "__main__":
    main()

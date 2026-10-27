#!/usr/bin/env python3
"""Print the most recent resumable Claude Code sessions as a JSON array.

Usage: resumable.py [limit] [--all]
Each entry: {id, title, summary, cwd, mtime, model, tokens, lastCall, ttl, sameModel}.
`summary` is the start of Claude's last reply (the first prompt if none).
Newest first, empty sessions skipped. Sessions whose folder is gone are left
out too, unless --all (the History tab): those come with "missing": true.

The prompt cache lives for `ttl` seconds after the last API call (`lastCall`)
and only for the model that made it, so a resume is cached when it happens
before lastCall + ttl and Claude would resume on that same model. Otherwise
the whole `tokens` of context is sent again.
"""
import glob
import json
import os
import re
import sys
from datetime import datetime

ARGS = [a for a in sys.argv[1:] if a != "--all"]
ALL = "--all" in sys.argv[1:]
LIMIT = int(ARGS[0]) if ARGS else 6
PROJECTS = os.path.expanduser("~/.claude/projects")


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def default_model(cwd):
    """The model `claude --resume` starts on in cwd: project settings win."""
    model = read_json(os.path.expanduser("~/.claude/settings.json")).get("model")
    for name in ("settings.json", "settings.local.json"):
        model = read_json(os.path.join(cwd, ".claude", name)).get("model") or model
    return model or ""


def same_model(alias, model_id):
    # Settings hold an alias ("opus") or a full id; transcripts hold the id.
    if not alias or not model_id:
        return False
    alias = alias.split("[")[0]
    return alias == model_id or alias in model_id.split("-")


def prompt_text(message):
    content = message.get("content")
    if isinstance(content, list):
        content = " ".join(p.get("text", "") for p in content if isinstance(p, dict))
    return (content or "").strip()


def new_state():
    return {"title": None, "cwd": None, "first_prompt": None, "last_reply": None,
            "model": None, "tokens": 0, "last_call": 0, "ttl": 300}


def scan(state, lines):
    """Fold transcript lines into state (what read_session sums up)."""
    for line in lines:
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if not isinstance(d, dict):
            continue
        kind = d.get("type")
        if kind == "ai-title":
            state["title"] = d.get("aiTitle") or state["title"]
        elif kind == "custom-title":
            state["title"] = d.get("customTitle") or state["title"]
        elif kind == "user" and not d.get("isSidechain"):
            state["cwd"] = state["cwd"] or d.get("cwd")
            if not state["first_prompt"]:
                text = prompt_text(d.get("message", {}))
                if text and not text.startswith("<"):
                    state["first_prompt"] = text
        elif kind == "assistant" and not d.get("isSidechain"):
            message = d.get("message", {})
            text = prompt_text(message)
            if text:
                state["last_reply"] = text
            usage = message.get("usage")
            if not usage or message.get("model", "").startswith("<"):
                continue
            state["model"] = message.get("model")
            state["tokens"] = (usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0)
                               + usage.get("cache_creation_input_tokens", 0) + usage.get("output_tokens", 0))
            created = usage.get("cache_creation") or {}
            if created.get("ephemeral_1h_input_tokens"):
                state["ttl"] = 3600
            elif created.get("ephemeral_5m_input_tokens"):
                state["ttl"] = 300
            try:
                state["last_call"] = int(datetime.fromisoformat(d["timestamp"].replace("Z", "+00:00")).timestamp())
            except (KeyError, ValueError):
                pass
        if state["cwd"] is None:
            state["cwd"] = d.get("cwd")


def summarize(state):
    title, first_prompt, last_reply = state["title"], state["first_prompt"], state["last_reply"]
    if not (title or first_prompt):
        return None
    title = (title or first_prompt).replace("\n", " ")
    summary = " ".join(re.sub(r"[*`#]+|\[([^\]]*)\]\([^)]*\)", lambda m: m.group(1) or "", last_reply or first_prompt or "").split())
    return {"title": title[:80], "summary": summary[:160], "cwd": state["cwd"], "model": state["model"] or "",
            "tokens": state["tokens"], "lastCall": state["last_call"], "ttl": state["ttl"]}


# What each transcript adds up to, kept between runs: every island open used
# to read every transcript on disk in full. A file that grew is read from
# where the last run stopped; one that changed any other way, from the top.
CACHE_PATH = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "clawdius", "resumable.json")
CACHE_VERSION = 2


def load_cache():
    try:
        with open(CACHE_PATH) as f:
            data = json.load(f)
        if isinstance(data, dict) and data.get("version") == CACHE_VERSION and isinstance(data.get("files"), dict):
            return data["files"]
    except (OSError, ValueError):
        pass
    return {}


def private_dir(path):
    """The folder, owner-only (an old one too): what's kept in it is private."""
    os.makedirs(path, mode=0o700, exist_ok=True)
    os.chmod(path, 0o700)


def save_cache(files):
    try:
        private_dir(os.path.dirname(CACHE_PATH))
        tmp = "%s.%d.tmp" % (CACHE_PATH, os.getpid())
        with os.fdopen(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
            json.dump({"version": CACHE_VERSION, "files": files}, f, separators=(",", ":"))
        os.replace(tmp, CACHE_PATH)
    except OSError:
        pass


def read_session(path, st, cache):
    """The session's summary, reading only what the cache hasn't seen."""
    entry = cache.get(path)
    if entry and entry.get("mtime") == st.st_mtime_ns and entry.get("size") == st.st_size:
        return entry["info"], False
    with open(path, "rb") as f:
        head = f.read(256).hex()
        # Grown with the same start: carry on. Anything else: from the top.
        if (entry and entry.get("head") == head and entry.get("size", 0) <= st.st_size
                and entry.get("offset", 0) <= st.st_size and isinstance(entry.get("state"), dict)):
            state, offset = dict(entry["state"]), entry["offset"]
        else:
            state, offset = new_state(), 0
        f.seek(offset)
        chunk = f.read()
    # Only whole lines move the offset on; a last line still being written is
    # read (as before) but read again next time, which changes nothing.
    end = chunk.rfind(b"\n") + 1
    scan(state, chunk[:end].decode("utf-8", "replace").split("\n"))
    done = dict(state)
    if end < len(chunk):
        scan(done, [chunk[end:].decode("utf-8", "replace")])
    info = summarize(done)
    cache[path] = {"mtime": st.st_mtime_ns, "size": st.st_size, "head": head, "offset": offset + end, "state": state, "info": info}
    return info, True


cache = load_cache()
files = []
for path in glob.glob(os.path.join(PROJECTS, "*", "*.jsonl")):
    try:
        files.append((path, os.stat(path)))
    except OSError:
        pass
files.sort(key=lambda f: f[1].st_mtime, reverse=True)
changed = False
models = {}
out = []
for path, st in files:
    if len(out) >= LIMIT:
        break
    try:
        info, fresh = read_session(path, st, cache)
    except OSError:
        continue
    changed = changed or fresh
    if not info:
        continue
    info = dict(info)
    found = bool(info["cwd"]) and os.path.isdir(info["cwd"])
    if found or ALL:
        info["id"] = os.path.basename(path)[:-6]
        info["mtime"] = int(st.st_mtime)
        if found and info["cwd"] not in models:
            models[info["cwd"]] = default_model(info["cwd"])
        info["sameModel"] = found and same_model(models[info["cwd"]], info["model"])
        info["cwd"] = info["cwd"] or ""
        if not found:
            info["missing"] = True
        out.append(info)
live = {path for path, _ in files}
if changed or any(p not in live for p in cache):
    save_cache({p: e for p, e in cache.items() if p in live})
print(json.dumps(out))

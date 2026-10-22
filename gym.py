#!/usr/bin/env python3
"""Daily reps: one small exercise a day, written by hand, from Exercism's tracks.

  gym.py today                  pick today's rep if there isn't one (and refresh the info)
  gym.py start                  copy today's rep into its folder; prints the file to open
  gym.py check                  run its tests; all passing counts the day
  gym.py easier | skip          another rep for today: a level down, or the same level
  gym.py set LANG on|off        a language in or out of the rotation (on sets it up)
  gym.py level LANG N           its level, 1-10 (Exercism's difficulty)
  gym.py setup LANG             clone its track (JavaScript: install jest once)

Everything lands in $XDG_STATE_HOME/clawdius/gym.json, which the widget
watches; nothing else writes it. Tracks are shallow clones of
github.com/exercism/<lang> under $XDG_DATA_HOME/clawdius/tracks, reps go to
~/Work/gym/<lang>/<slug> ($CLAWDIUS_GYM_ROOT moves it). A rep is the
exercise's stub, tests and instructions, never its example solution, and
every test runs (Exercism skips all but the first).
"""
import fcntl
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import date, timedelta

STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "clawdius")
STATE = os.path.join(STATE_DIR, "gym.json")
TRACKS = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "clawdius", "tracks")
REPS = os.path.expanduser(os.environ.get("CLAWDIUS_GYM_ROOT") or "~/Work/gym")
START_LEVEL = 2
PASSES_TO_LEVEL_UP = 2
SKIP_DAYS = 30
TEST_TIMEOUT = 180
# The JavaScript reps share one jest install: these, at the versions the
# track's exercises ask for.
JEST_DEPS = ("@exercism/babel-preset-javascript", "@jest/globals", "babel-jest", "core-js", "expect", "jest")

LANGS = {
    "javascript": {"name": "JavaScript", "needs": ["node", "npm"],
                   "install": "sudo pacman -S nodejs npm"},
    "rust": {"name": "Rust", "needs": ["cargo"],
             "install": "sudo pacman -S rustup && rustup default stable"},
}


def today_str():
    return date.today().isoformat()


def track_dir(lang):
    return os.path.join(TRACKS, lang)


def read_json(path, fallback):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return fallback


def load():
    state = read_json(STATE, {})
    state.setdefault("langs", {})
    state.setdefault("today", None)
    state.setdefault("done", [])
    state.setdefault("skipped", {})
    state.setdefault("streak", {"count": 0, "last": ""})
    for lang in LANGS:
        state["langs"].setdefault(lang, {"on": False, "level": START_LEVEL, "passes": 0})
    return state


def info(lang):
    missing = [tool for tool in LANGS[lang]["needs"] if not shutil.which(tool)]
    cloned = os.path.isfile(os.path.join(track_dir(lang), "config.json"))
    installed = lang != "javascript" or os.path.isdir(os.path.join(REPS, "javascript", "node_modules"))
    return {"name": LANGS[lang]["name"], "missing": missing, "install": LANGS[lang]["install"],
            "setUp": cloned and installed, "ready": not missing and cloned and installed}


def save(state):
    # What the widget shows but can't work out itself, refreshed on every save.
    state["info"] = {lang: info(lang) for lang in LANGS}
    last = state["streak"].get("last", "")
    alive = last in (today_str(), (date.today() - timedelta(days=1)).isoformat())
    state["streakNow"] = state["streak"].get("count", 0) if alive else 0
    state["reps"] = REPS
    os.makedirs(STATE_DIR, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=".gym-")
    with os.fdopen(fd, "w") as f:
        json.dump(state, f, indent=1)
    os.replace(tmp, STATE)


def catalogue(lang):
    config = read_json(os.path.join(track_dir(lang), "config.json"), {})
    out = []
    for e in config.get("exercises", {}).get("practice", []):
        if e.get("status") == "deprecated" or e.get("slug") == "hello-world":
            continue
        if os.path.isdir(os.path.join(track_dir(lang), "exercises", "practice", e["slug"])):
            out.append(e)
    return out


def exercise_meta(lang, slug):
    return read_json(os.path.join(track_dir(lang), "exercises", "practice", slug, ".meta", "config.json"), {})


def rotation(state):
    return sorted(l for l in LANGS if state["langs"][l]["on"] and info(l)["ready"])


def pick(state, lang=None):
    """Today's rep: the language rotates by day, the exercise is the unsolved,
    not lately skipped one nearest the language's level. The same day always
    picks the same."""
    langs = rotation(state)
    if lang not in langs:
        if not langs:
            state["today"] = None
            return
        lang = langs[date.today().toordinal() % len(langs)]
    level = state["langs"][lang]["level"]
    done = {d["slug"] for d in state["done"] if d["lang"] == lang}
    cutoff = (date.today() - timedelta(days=SKIP_DAYS)).isoformat()
    skipped = {k for k, day in state["skipped"].items() if day >= cutoff}
    exercises = catalogue(lang)
    fresh = [e for e in exercises if e["slug"] not in done and lang + "/" + e["slug"] not in skipped]
    pool = fresh or [e for e in exercises if lang + "/" + e["slug"] not in skipped] or exercises
    if not pool:
        state["today"] = None
        return
    salt = today_str() + str(len(state["skipped"]))

    def rank(e):
        tie = hashlib.md5((salt + e["slug"]).encode()).hexdigest()
        return (abs(e.get("difficulty", 1) - level), tie)

    e = min(pool, key=rank)
    meta = exercise_meta(lang, e["slug"])
    # The track's own solution, for Claude's review to compare against.
    example = meta.get("files", {}).get("example", [])
    example = os.path.join(track_dir(lang), "exercises", "practice", e["slug"], example[0]) if example else ""
    state["today"] = {"date": today_str(), "lang": lang, "slug": e["slug"], "name": e.get("name", e["slug"]),
                      "blurb": meta.get("blurb", ""), "difficulty": e.get("difficulty", 1), "level": level,
                      "example": example, "dir": "", "file": "", "startedAt": 0, "passedAt": 0, "check": None}


def ensure_today(state):
    t = state["today"]
    stale = not t or t.get("date") != today_str()
    # Its language taken out of the rotation before it was started.
    dropped = t and not t.get("startedAt") and t.get("lang") not in rotation(state)
    if stale or dropped:
        pick(state)


def unskip(lang, path):
    with open(path) as f:
        text = f.read()
    if lang == "javascript":
        text = re.sub(r"\bxtest\(", "test(", text)
    elif lang == "rust":
        text = re.sub(r"^[ \t]*#\[ignore\][ \t]*\n", "", text, flags=re.M)
    with open(path, "w") as f:
        f.write(text)


def start(state):
    t = state["today"]
    if not t:
        sys.stderr.write("no rep today: turn a language on in Settings\n")
        return 1
    lang, slug = t["lang"], t["slug"]
    dest = os.path.join(REPS, lang, slug)
    files = exercise_meta(lang, slug).get("files", {})
    if not os.path.isdir(dest):
        # A rep started on an earlier day keeps what was written in it.
        src = os.path.join(track_dir(lang), "exercises", "practice", slug)
        shutil.copytree(src, dest, ignore=shutil.ignore_patterns(".meta"))
        for test in files.get("test", []):
            unskip(lang, os.path.join(dest, test))
    solution = [f for f in files.get("solution", []) if not f.endswith(".toml")]
    t["dir"] = dest
    t["file"] = os.path.join(dest, solution[0]) if solution else dest
    t["startedAt"] = t.get("startedAt") or int(time.time() * 1000)
    save(state)
    print(t["file"])
    return 0


ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def tail(text, n=12):
    lines = [ANSI.sub("", l).rstrip() for l in text.splitlines()]
    return "\n".join([l for l in lines if l.strip()][-n:])


def run_tests(lang, folder):
    """(passed, total, output) for the rep in folder."""
    env = dict(os.environ, FORCE_COLOR="0", NO_COLOR="1", CARGO_TERM_COLOR="never")
    if lang == "rust":
        p = subprocess.run(["cargo", "test"], cwd=folder, env=env, capture_output=True, text=True, timeout=TEST_TIMEOUT)
        out = p.stdout + p.stderr
        passed = failed = 0
        for m in re.finditer(r"test result: \w+\. (\d+) passed; (\d+) failed", out):
            passed += int(m.group(1))
            failed += int(m.group(2))
        return passed, passed + failed, out
    jest = os.path.join(REPS, "javascript", "node_modules", ".bin", "jest")
    with tempfile.NamedTemporaryFile(suffix=".json") as report:
        p = subprocess.run([jest, "--ci", "--json", "--outputFile", report.name], cwd=folder, env=env,
                           capture_output=True, text=True, timeout=TEST_TIMEOUT)
        result = read_json(report.name, {})
    out = re.sub(r"^Test results written to.*$", "", p.stdout + p.stderr, flags=re.M)
    return result.get("numPassedTests", 0), result.get("numTotalTests", 0), out


def check(state):
    t = state["today"]
    if not t or not t.get("dir"):
        sys.stderr.write("start today's rep first\n")
        return 1
    try:
        passed, total, out = run_tests(t["lang"], t["dir"])
    except subprocess.TimeoutExpired:
        passed, total, out = 0, 0, "The tests took over %ds and were stopped." % TEST_TIMEOUT
    t["check"] = {"passed": passed, "total": total, "at": int(time.time() * 1000), "tail": tail(out)}
    if total and passed == total and not t.get("passedAt"):
        t["passedAt"] = t["check"]["at"]
        state["done"].append({"date": today_str(), "lang": t["lang"], "slug": t["slug"]})
        lang = state["langs"][t["lang"]]
        lang["passes"] = lang.get("passes", 0) + 1
        if lang["passes"] >= PASSES_TO_LEVEL_UP and lang["level"] < 10:
            lang["level"] += 1
            lang["passes"] = 0
        streak = state["streak"]
        if streak.get("last") != today_str():
            yesterday = (date.today() - timedelta(days=1)).isoformat()
            streak["count"] = streak.get("count", 0) + 1 if streak.get("last") == yesterday else 1
            streak["last"] = today_str()
    save(state)
    return 0


def setup(lang):
    track = track_dir(lang)
    if not os.path.isfile(os.path.join(track, "config.json")):
        os.makedirs(TRACKS, exist_ok=True)
        shutil.rmtree(track, ignore_errors=True)
        p = subprocess.run(["git", "clone", "-q", "--depth", "1", "https://github.com/exercism/" + lang, track],
                           capture_output=True, text=True)
        if p.returncode != 0:
            sys.stderr.write("couldn't get the %s track: %s\n" % (LANGS[lang]["name"], p.stderr.strip()))
            return 1
    if lang == "javascript":
        root = os.path.join(REPS, "javascript")
        if not os.path.isdir(os.path.join(root, "node_modules")):
            sample = read_json(os.path.join(track, "exercises", "practice", "two-fer", "package.json"), {})
            deps = {k: v for k, v in sample.get("devDependencies", {}).items() if k in JEST_DEPS}
            os.makedirs(root, exist_ok=True)
            with open(os.path.join(root, "package.json"), "w") as f:
                json.dump({"name": "clawdius-reps", "private": True, "devDependencies": deps}, f, indent=2)
            p = subprocess.run(["npm", "install", "--no-audit", "--no-fund", "--loglevel=error"], cwd=root,
                               capture_output=True, text=True)
            if p.returncode != 0:
                shutil.rmtree(os.path.join(root, "node_modules"), ignore_errors=True)
                sys.stderr.write("npm install failed: %s\n" % tail(p.stderr, 3))
                return 1
    return 0


def main(args):
    if not args:
        sys.stderr.write(__doc__)
        return 2
    cmd = args[0]
    lang = args[1] if len(args) > 1 else ""
    if cmd in ("set", "level", "setup") and lang not in LANGS:
        sys.stderr.write("unknown language %r (%s)\n" % (lang, ", ".join(LANGS)))
        return 2
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(os.path.join(STATE_DIR, "gym.lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = load()
        code = 0
        if cmd == "today":
            ensure_today(state)
        elif cmd == "start":
            ensure_today(state)
            return start(state)
        elif cmd == "check":
            return check(state)
        elif cmd in ("easier", "skip"):
            t = state["today"]
            if t:
                if cmd == "easier":
                    l = state["langs"][t["lang"]]
                    l["level"] = max(1, l["level"] - 1)
                    l["passes"] = 0
                else:
                    state["skipped"][t["lang"] + "/" + t["slug"]] = today_str()
                pick(state, t["lang"])
        elif cmd == "set" and len(args) == 3 and args[2] in ("on", "off"):
            state["langs"][lang]["on"] = args[2] == "on"
            if args[2] == "on" and not info(lang)["missing"]:
                code = setup(lang)
            ensure_today(state)
        elif cmd == "level" and len(args) == 3 and args[2].isdigit():
            state["langs"][lang]["level"] = max(1, min(10, int(args[2])))
            state["langs"][lang]["passes"] = 0
            t = state["today"]
            if t and t["lang"] == lang and not t.get("startedAt"):
                pick(state, lang)
        elif cmd == "setup":
            code = setup(lang)
            ensure_today(state)
        else:
            sys.stderr.write(__doc__)
            return 2
        save(state)
        return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
